# Converts a square JPG/PNG into a multi-size Windows icon (.ico)
# Usage: powershell -ExecutionPolicy Bypass -File tool\make_icon.ps1 -Source "assets\AP ICON.jpg" -Output "windows\runner\resources\app_icon.ico"
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads .ps1 as ANSI).
# NOTE: the parameter is named -Source on purpose: $input is an automatic variable.
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Output,
  [int[]]$Sizes = @(16, 24, 32, 48, 64, 128, 256)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src = if ([System.IO.Path]::IsPathRooted($Source)) { $Source } else { Join-Path $root $Source }
$dst = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $root $Output }
if (-not (Test-Path -LiteralPath $src)) { throw "Source image not found: $src" }

$img = [System.Drawing.Image]::FromFile($src)
try {
  # Center-crop to a square when the source is not square.
  $side = [Math]::Min($img.Width, $img.Height)
  $srcRect = New-Object System.Drawing.Rectangle 0, 0, $side, $side

  $entries = @()
  foreach ($size in $Sizes) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $size, $size), $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
      } finally { $g.Dispose() }

      # Raw 32-bit BGRA pixels (DIB) instead of PNG-in-ICO: maximum
      # compatibility with GDI+, Explorer and installer tooling.
      $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
      $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
      try {
        $xor = New-Object byte[] ($data.Stride * $size)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $xor, 0, $xor.Length)
        $andStride = [int](([Math]::Ceiling($size / 32.0)) * 4)
        $and = New-Object byte[] ($andStride * $size)

        $hdr = New-Object byte[] 40
        [Array]::Copy([BitConverter]::GetBytes([Int32]40), 0, $hdr, 0, 4)   # biSize
        [Array]::Copy([BitConverter]::GetBytes([Int32]$size), 0, $hdr, 4, 4)  # biWidth
        [Array]::Copy([BitConverter]::GetBytes([Int32]($size * 2)), 0, $hdr, 8, 4) # biHeight (XOR+AND)
        [Array]::Copy([BitConverter]::GetBytes([Int16]1), 0, $hdr, 12, 2)   # biPlanes
        [Array]::Copy([BitConverter]::GetBytes([Int16]32), 0, $hdr, 14, 2)  # biBitCount
        [Array]::Copy([BitConverter]::GetBytes([Int32]0), 0, $hdr, 16, 4)   # BI_RGB
        [Array]::Copy([BitConverter]::GetBytes([Int32]($xor.Length + $and.Length)), 0, $hdr, 20, 4) # biSizeImage

        $payload = New-Object byte[] (40 + $xor.Length + $and.Length)
        [Array]::Copy($hdr, 0, $payload, 0, 40)
        [Array]::Copy($xor, 0, $payload, 40, $xor.Length)
        [Array]::Copy($and, 0, $payload, 40 + $xor.Length, $and.Length)
        $entries += ,@{ Size = $size; Data = $payload }
      } finally { $bmp.UnlockBits($data) }
    } finally { $bmp.Dispose() }
  }
} finally { $img.Dispose() }

# Assemble the .ico container.
$count = $entries.Count
$headerSize = 6
$entrySize = 16
$offset = $headerSize + ($entrySize * $count)
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $out
try {
  $w.Write([UInt16]0)       # reserved
  $w.Write([UInt16]1)       # type = icon
  $w.Write([UInt16]$count)  # image count
  foreach ($e in $entries) {
    $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $w.Write([Byte]$dim)          # width  (0 means 256)
    $w.Write([Byte]$dim)          # height (0 means 256)
    $w.Write([Byte]0)             # palette size
    $w.Write([Byte]0)             # reserved
    $w.Write([UInt16]1)           # color planes
    $w.Write([UInt16]32)          # bits per pixel
    $w.Write([UInt32]$e.Data.Length)
    $w.Write([UInt32]$offset)
    $offset += $e.Data.Length
  }
  foreach ($e in $entries) { $w.Write($e.Data) }
  $w.Flush()

  $dir = Split-Path -Parent $dst
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllBytes($dst, $out.ToArray())
  "ICO created: $dst  (sizes: $($Sizes -join ', '))  bytes: $((Get-Item -LiteralPath $dst).Length)"
} finally {
  $w.Dispose()
  $out.Dispose()
}