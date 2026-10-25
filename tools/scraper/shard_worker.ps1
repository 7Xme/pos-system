#requires -Version 5.1
<#
.SYNOPSIS
  One parallel worker that downloads its own share (shard) of the crawl.

.DESCRIPTION
  Runs repeated rounds of the resumable "pages" and "images" phases, each time
  restricted to this worker's slice (template id % Shards == Shard). Because the
  split is by template id, the N workers never fetch the same product/image.

  Progress is appended to data\logs\shard<Shard>.log.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\shard_worker.ps1 -Shard 0 -Shards 3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$Shard,
    [Parameter(Mandatory = $true)][int]$Shards,
    [int]$Passes = 4,
    [int]$PageConcurrency = 8,
    [int]$ImageConcurrency = 16
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
$env:PYTHONUNBUFFERED = '1'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..\..')).Path
$data = Join-Path $root 'data'
$logs = Join-Path $data 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

$log = Join-Path $logs "shard$Shard.log"

function Write-Log([string]$Message) {
    $line = '[{0}] shard{1}/{2}: {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Shard, $Shards, $Message
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

function Get-CrawlStatus {
    $raw = & python (Join-Path $here 'status.py') --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

Write-Log "start (pages conc=$PageConcurrency, images conc=$ImageConcurrency, passes=$Passes)"
Push-Location $here
try {
    for ($pass = 1; $pass -le $Passes; $pass++) {
        $s = Get-CrawlStatus
        if ($null -ne $s -and $s.missing_products -le 0 -and $s.missing_images -le 0) {
            Write-Log 'nothing missing globally - done'
            break
        }

        Write-Log ("round {0}/{1}: pages (missing_products={2})" -f $pass, $Passes, $s.missing_products)
        & python scrape.py pages --concurrency $PageConcurrency --retries 5 --shard $Shard --shards $Shards *>> $log
        Write-Log ("round {0}: pages exit={1}" -f $pass, $LASTEXITCODE)

        $s2 = Get-CrawlStatus
        if ($null -ne $s2 -and $s2.missing_images -le 0) {
            Write-Log 'no missing images - skipping image round'
            Start-Sleep -Seconds 5
            continue
        }

        Write-Log ("round {0}/{1}: images (missing_images={2})" -f $pass, $Passes, $s2.missing_images)
        & python scrape.py images --concurrency $ImageConcurrency --retries 5 --shard $Shard --shards $Shards *>> $log
        Write-Log ("round {0}: images exit={1}" -f $pass, $LASTEXITCODE)

        Start-Sleep -Seconds 5
    }
}
finally {
    Pop-Location
}

$final = Get-CrawlStatus
if ($null -ne $final) {
    Write-Log ("end - products={0} images={1} missing_products={2} missing_images={3}" -f `
        $final.products_unique, $final.images_present, $final.missing_products, $final.missing_images)
}
Write-Log 'shard worker finished'
