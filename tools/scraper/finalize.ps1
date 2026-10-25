#requires -Version 5.1
<#
.SYNOPSIS
  Finalise the almouggar crawl without manual babysitting.

.DESCRIPTION
  Waits for the initial page crawl to finish, retries failed product pages,
  finishes the image downloads, then rebuilds and validates the Drift SQLite
  database. Progress is appended to data\logs\finalize.log and a
  data\.finalized marker is written only after validation passes.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize.ps1
#>
[CmdletBinding()]
param(
    [int]$MaxPagesPasses  = 6,
    [int]$MaxImagesPasses = 8,
    [int]$MaxWaitHours    = 14,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..\..')).Path
$data = Join-Path $root 'data'
$logs = Join-Path $data 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

$log = Join-Path $logs 'finalize.log'
$pagesMarker = Join-Path $data '.pages_complete'
$finalMarker = Join-Path $data '.finalized'
$statusScript = Join-Path $here 'status.py'

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

function Get-CrawlStatus {
    $raw = & python $statusScript --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Get-ScrapeProcesses([string]$Phase) {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^python(w)?\.exe$' -and
            $_.CommandLine -and
            $_.CommandLine -like '*scrape.py*' -and
            $_.CommandLine -like "*$Phase*"
        }
}

function Wait-ScrapeExit([string]$Phase, [int]$Hours) {
    $deadline = (Get-Date).AddHours($Hours)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-ScrapeProcesses $Phase)) { return $true }
        Start-Sleep -Seconds 30
    }
    return $false
}

function Invoke-Scrape([string]$Phase, [string[]]$Extra) {
    $argv = @($Phase) + $Extra
    & python (Join-Path $here 'scrape.py') @argv *>> $log
    return $LASTEXITCODE
}

if ((Test-Path $finalMarker) -and -not $Force) {
    Write-Log 'finalize: already completed (data\.finalized). Use -Force to rerun.'
    exit 0
}

Write-Log "finalize: start (root=$root)"

# ── 1) wait for the initial page crawl ─────────────────────────────────────
if (-not (Test-Path $pagesMarker)) {
    Write-Log "finalize: waiting for $pagesMarker (max $MaxWaitHours h)"
    $deadline = (Get-Date).AddHours($MaxWaitHours)
    while (-not (Test-Path $pagesMarker)) {
        if ((Get-Date) -gt $deadline) {
            Write-Log 'finalize: timed out waiting for the page crawl - aborting.'
            exit 1
        }
        Start-Sleep -Seconds 60
    }
}
Write-Log 'finalize: pages marker found; letting the page process exit'
Wait-ScrapeExit 'pages' 1 | Out-Null

# ── 2) retry failed / missing product pages ────────────────────────────────
$before = Get-CrawlStatus
if ($null -ne $before) {
    Write-Log ("finalize: pages done={0} missing={1} errors={2}" -f `
        $before.products_unique, $before.missing_products, $before.errors_logged)
}

for ($pass = 1; $pass -le $MaxPagesPasses; $pass++) {
    $s = Get-CrawlStatus
    if ($null -eq $s) { Write-Log 'finalize: status unavailable - stopping page retries'; break }
    if ($s.missing_products -le 0) { Write-Log 'finalize: no missing products'; break }

    Write-Log ("finalize: page retry pass {0}/{1} - missing={2}" -f `
        $pass, $MaxPagesPasses, $s.missing_products)
    $code = Invoke-Scrape 'pages' @('--concurrency', '6', '--retries', '5')
    Write-Log "finalize: page retry pass $pass exit=$code"

    $after = Get-CrawlStatus
    if ($null -ne $after -and $after.products_unique -le $s.products_unique) {
        Write-Log 'finalize: no new products in this pass - remaining URLs are unrecoverable (404?)'
        break
    }
    Start-Sleep -Seconds 60
}

# ── 3) finish images ───────────────────────────────────────────────────────
Write-Log 'finalize: waiting for any running image process to exit'
if (-not (Wait-ScrapeExit 'images' 8)) {
    Write-Log 'finalize: image process still running after 8 h - continuing anyway'
}

for ($pass = 1; $pass -le $MaxImagesPasses; $pass++) {
    $s = Get-CrawlStatus
    if ($null -eq $s) { Write-Log 'finalize: status unavailable - stopping image retries'; break }
    if ($s.missing_images -le 0) { Write-Log 'finalize: no missing images'; break }

    Write-Log ("finalize: image pass {0}/{1} - missing={2} present={3}" -f `
        $pass, $MaxImagesPasses, $s.missing_images, $s.images_present)
    $code = Invoke-Scrape 'images' @('--concurrency', '12', '--retries', '5')
    Write-Log "finalize: image pass $pass exit=$code"

    $after = Get-CrawlStatus
    if ($null -ne $after -and $after.images_present -le $s.images_present) {
        Write-Log 'finalize: no new images in this pass - remaining downloads are unrecoverable'
        break
    }
    Start-Sleep -Seconds 30
}

# ── 4) rebuild + validate the database ─────────────────────────────────────
Write-Log 'finalize: building the SQLite catalogue'
& python (Join-Path $here 'build_db.py') --sql *>> $log
$buildCode = $LASTEXITCODE
Write-Log "finalize: build_db exit=$buildCode"
if ($buildCode -ne 0) { Write-Log 'finalize: build failed - aborting'; exit 1 }

$validation = & python (Join-Path $here 'validate_db.py') 2>&1
$valCode = $LASTEXITCODE
$validation | ForEach-Object { Add-Content -Path $log -Value $_ -Encoding UTF8 }
$valText = $validation -join "`n"
if ($valCode -ne 0 -or $valText -notmatch 'RESULT:\s*PASS') {
    Write-Log 'finalize: validation failed - see log'
    exit 1
}
Write-Log 'finalize: validation PASS'

& python (Join-Path $here 'report_data.py') *> (Join-Path $data 'report.txt')
Write-Log 'finalize: report written to data\report.txt'

$final = Get-CrawlStatus
if ($null -ne $final) {
    Write-Log ("finalize: done - products={0} images={1} missing_products={2} missing_images={3}" -f `
        $final.products_unique, $final.images_present, $final.missing_products, $final.missing_images)
}
(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content -Path $finalMarker -Encoding UTF8
Write-Log 'finalize: complete'
exit 0
