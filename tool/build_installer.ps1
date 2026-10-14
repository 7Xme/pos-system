# Builds the single-file YPOS installer (YPOS-Setup.exe).
# Pipeline: flutter build (release) -> zip the Release folder -> compile the
# C# stub (tool/ypos_installer.cs) with the ZIP embedded as a manifest resource.
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads .ps1 as ANSI).
param(
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
  $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe (.NET Framework) not found" }

$release = Join-Path $root "build\windows\x64\runner\Release"
$exe = Join-Path $release "YPOS.exe"
$icon = Join-Path $root "windows\runner\resources\app_icon.ico"
$payload = Join-Path $root "build\ypos_payload.zip"
$outExe = Join-Path $root "build\YPOS-Setup.exe"

if (-not $SkipFlutterBuild) {
  Write-Host "==> flutter build windows --release"
  & "C:\src\flutter\bin\flutter.bat" build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
}

if (-not (Test-Path -LiteralPath $exe)) { throw "YPOS.exe not found: $exe" }

Write-Host "==> Staging payload"
$stage = Join-Path $root "build\ypos_stage"
if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $release "*") -Destination $stage -Recurse -Force
Get-ChildItem -Path $stage -Recurse -Include *.pdb -File | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "==> Zipping payload"
if (Test-Path -LiteralPath $payload) { Remove-Item -Force $payload }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $payload,
  [System.IO.Compression.CompressionLevel]::Optimal, $false)

Write-Host "==> Compiling installer stub"
if (Test-Path -LiteralPath $outExe) { Remove-Item -Force $outExe }
$args = @(
  "/target:winexe",
  "/platform:x64",
  "/optimize+",
  "/nologo",
  "/out:$outExe",
  "/resource:$payload,YPOS.Installer.payload.zip",
  "/reference:System.dll",
  "/reference:System.Drawing.dll",
  "/reference:System.Windows.Forms.dll",
  "/reference:System.IO.Compression.dll",
  "/reference:System.IO.Compression.FileSystem.dll"
)
if (Test-Path -LiteralPath $icon) { $args += "/win32icon:$icon" }
$args += (Join-Path $root "tool\ypos_installer.cs")

& $csc $args
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }

Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
$mb = [Math]::Round((Get-Item -LiteralPath $outExe).Length / 1MB, 1)
Write-Host "OK: $outExe  ($mb MB, single file)"
$v = (Get-Item -LiteralPath $outExe).VersionInfo
Write-Host "    ProductName=$($v.ProductName)  FileDescription=$($v.FileDescription)"
