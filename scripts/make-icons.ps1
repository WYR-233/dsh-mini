# make-icons.ps1 - build themed icons from generated art.
#   uninstall.ico  = crying whale-maid (shown for the uninstaller and in
#                    Windows Settings > Apps)
#   welcome.ico    = waving whale-maid (setup.exe icon)
# Both are multi-size ICO (16/24/32/48/64/128/256), zero deps (GDI+).
param(
    [string]$CryPng = "G:\Comfy-Desktop\ComfyUI-Shared\output\dshmini_cry_00002_.png",
    [string]$WavePng = "G:\Comfy-Desktop\ComfyUI-Shared\output\dshmini_wizard_tall_00001_.png"
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $repoRoot 'assets'

Add-Type -AssemblyName System.Drawing

function Convert-PngToIco([string]$Png, [string]$Ico, $Crop) {
    $src = [System.Drawing.Image]::FromFile($Png)
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngList = New-Object 'System.Collections.Generic.List[byte[]]'

    if ($null -eq $Crop) {
        $Crop = New-Object System.Drawing.Rectangle(0, 0, $src.Width, $src.Height)
    }

    foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $s, $s)), $Crop, [System.Drawing.GraphicsUnit]::Pixel)
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngList.Add($ms.ToArray())
        $g.Dispose(); $bmp.Dispose(); $ms.Dispose()
    }
    $src.Dispose()

    $count = $sizes.Count
    $headerSize = 6 + 16 * $count
    $totalSize = $headerSize
    foreach ($b in $pngList) { $totalSize += $b.Length }

    $fs = [System.IO.File]::Create($Ico)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$count)
    $offset = $headerSize
    for ($i = 0; $i -lt $count; $i++) {
        $s = $sizes[$i]
        $b = $pngList[$i]
        $dim = if ($s -ge 256) { 0 } else { $s }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim)
        $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$b.Length)
        $bw.Write([UInt32]$offset)
        $offset += $b.Length
    }
    foreach ($b in $pngList) { $bw.Write($b) }
    $bw.Close(); $fs.Close()
    Write-Host "OK $Ico ($totalSize bytes, $count sizes)"
}

# uninstall: whole 512x512 crying art
Convert-PngToIco $CryPng (Join-Path $assets 'uninstall.ico') $null

# welcome: crop the TOP 512x512 square of the tall waving art (head + wave)
Convert-PngToIco $WavePng (Join-Path $assets 'welcome.ico') (New-Object System.Drawing.Rectangle(0, 0, 512, 512))
