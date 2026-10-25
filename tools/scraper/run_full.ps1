# Full almouggar.com import pipeline.
#
#   pages  : 99 430 product pages  -> %ROOT%\data\products.jsonl
#   images : 99 430 product images -> %ROOT%\data\product_images\
#
# Both phases are resumable - re-running this script after an interruption
# simply continues where it stopped.
#
#   powershell -File tools\scraper\run_full.ps1
#   powershell -File tools\scraper\run_full.ps1 -PageConcurrency 64 -ImageConcurrency 24

param(
    [int]$PageConcurrency = 64,
    [int]$ImageConcurrency = 24
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $here '..\..')
$dataDir = Join-Path $root 'data'
$logDir = Join-Path $dataDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host "root      : $root"
Write-Host "logs      : $logDir"
Write-Host "pages     : concurrency $PageConcurrency"
Write-Host "images    : concurrency $ImageConcurrency"

# Make sure the URL list exists before starting the crawlers.
if (-not (Test-Path (Join-Path $dataDir 'product_urls.txt'))) {
    Write-Host "collecting product urls..."
    & python (Join-Path $here 'collect_urls.py')
}

$env:PYTHONUNBUFFERED = '1'
Push-Location $here
try {
    $pages = Start-Process -FilePath 'python' `
        -ArgumentList @('scrape.py', 'pages', '--concurrency', $PageConcurrency) `
        -RedirectStandardOutput (Join-Path $logDir 'pages.out.log') `
        -RedirectStandardError (Join-Path $logDir 'pages.err.log') `
        -WindowStyle Hidden -PassThru

    $images = Start-Process -FilePath 'python' `
        -ArgumentList @('scrape.py', 'images', '--concurrency', $ImageConcurrency, '--follow') `
        -RedirectStandardOutput (Join-Path $logDir 'images.out.log') `
        -RedirectStandardError (Join-Path $logDir 'images.err.log') `
        -WindowStyle Hidden -PassThru
}
finally {
    Pop-Location
}

Write-Host "pages  PID : $($pages.Id)"
Write-Host "images PID : $($images.Id)"
Write-Host ""
Write-Host "Watch progress:"
Write-Host "  Get-Content '$logDir\pages.out.log'  -Tail 1"
Write-Host "  Get-Content '$logDir\images.out.log' -Tail 1"
Write-Host ""
Write-Host "Then build the database:"
Write-Host "  python tools\scraper\build_db.py --sql"
