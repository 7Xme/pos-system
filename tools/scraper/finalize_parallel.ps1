#requires -Version 5.1
<#
.SYNOPSIS
  Fast parallel finaliser: N workers download disjoint shares, then DB is built.

.DESCRIPTION
  Starts `Shards` copies of shard_worker.ps1 (default 3). Each worker only
  fetches template ids where id % Shards == its index, so there is no overlap.
  When every worker exits, the SQLite catalogue is rebuilt and validated, and
  data\.finalized is written.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize_parallel.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize_parallel.ps1 -Shards 3 -ImageConcurrency 16
#>
[CmdletBinding()]
param(
    [int]$Shards = 3,
    [int]$Passes = 4,
    [int]$PageConcurrency = 8,
    [int]$ImageConcurrency = 16
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..\..')).Path
$data = Join-Path $root 'data'
$logs = Join-Path $data 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

$log = Join-Path $logs 'finalize_parallel.log'
$finalMarker = Join-Path $data '.finalized'
$worker = Join-Path $here 'shard_worker.ps1'

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

if (Test-Path $finalMarker) { Remove-Item $finalMarker -Force -ErrorAction SilentlyContinue }

Write-Log ("parallel finalize: start - shards={0} pages_conc={1} images_conc={2} passes={3}" -f `
    $Shards, $PageConcurrency, $ImageConcurrency, $Passes)

$procs = @()
for ($i = 0; $i -lt $Shards; $i++) {
    $p = Start-Process -FilePath 'powershell' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker,
        '-Shard', $i, '-Shards', $Shards, '-Passes', $Passes,
        '-PageConcurrency', $PageConcurrency, '-ImageConcurrency', $ImageConcurrency
    ) -WorkingDirectory $here -WindowStyle Hidden -PassThru
    $procs += $p
    Write-Log ("launched shard {0}/{1} pid={2}" -f $i, $Shards, $p.Id)
}

foreach ($p in $procs) { $p.WaitForExit() | Out-Null }
Write-Log 'all shard workers exited'

# ── rebuild + validate the database ───────────────────────────────────────
Write-Log 'building the SQLite catalogue'
& python (Join-Path $here 'build_db.py') --sql *>> $log
$buildCode = $LASTEXITCODE
Write-Log "build_db exit=$buildCode"
if ($buildCode -ne 0) { Write-Log 'build failed - aborting'; exit 1 }

$validation = & python (Join-Path $here 'validate_db.py') 2>&1
$valCode = $LASTEXITCODE
$validation | ForEach-Object { Add-Content -Path $log -Value $_ -Encoding UTF8 }
if ($valCode -ne 0 -or (($validation -join "`n") -notmatch 'RESULT:\s*PASS')) {
    Write-Log 'validation failed - see log'
    exit 1
}
Write-Log 'validation PASS'

& python (Join-Path $here 'report_data.py') *> (Join-Path $data 'report.txt')
Write-Log 'report written to data\report.txt'

(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content -Path $finalMarker -Encoding UTF8
Write-Log 'parallel finalize: complete'
exit 0
