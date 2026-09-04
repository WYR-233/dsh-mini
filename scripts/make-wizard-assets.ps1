# make-wizard-assets.ps1 - convert generated art into Inno wizard BMPs.
# wizard-whale.bmp (WizardImageFile, 410x785): the "lying on desk" whale
#   maid, aspect-fit centered (NO stretching), pale gradient around it.
# wizard-bg.bmp (whole-window background, ~800x600): the "eating rice" Q
#   whale maid faded to ~30%, aspect-fit centered on a pale gradient.
#   The installer paints it behind every wizard page ([Code] in the iss).
# wizard-small.bmp (55x55): solid pale-blue background, no transparency
#   tricks - the square blends into the page invisibly.
param(
    [string]$WizardPng = "G:\deepseek\deepseek-harness\.build\whale-desktop-big.png",
    [string]$BgPng = "G:\deepseek\deepseek-harness\.build\whale-tray.png",
    [string]$SmallPng = "G:\deepseek\deepseek-harness\.build\whale-tray.png"
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $repoRoot 'assets'

Add-Type -AssemblyName System.Drawing

$top = [System.Drawing.Color]::FromArgb(255, 244, 246, 251)
$bottom = [System.Drawing.Color]::FromArgb(255, 212, 231, 248)

function New-GradientCanvas([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 90)
    $g.FillRectangle($brush, $rect)
    return @($bmp, $g)
}

function Draw-Contain([System.Drawing.Graphics]$g, [System.Drawing.Image]$src, [int]$w, [int]$h, [double]$alpha) {
    $scale = [math]::Min($w / $src.Width, $h / $src.Height)
    $dw = [int]($src.Width * $scale); $dh = [int]($src.Height * $scale)
    $dx = [int](($w - $dw) / 2); $dy = [int](($h - $dh) / 2)
    $cm = New-Object System.Drawing.Imaging.ColorMatrix
    $cm.Matrix33 = $alpha
    $ia = New-Object System.Drawing.Imaging.ImageAttributes
    $ia.SetColorMatrix($cm)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)), 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
}

# ---- wizard image (right-side panel): aspect-fit, no squeeze ----
$w = 410; $h = 785
$r = New-GradientCanvas $w $h
$wbmp = $r[0]; $wg = $r[1]
$wsrc = [System.Drawing.Image]::FromFile($WizardPng)
Draw-Contain $wg $wsrc $w $h 0.85
$wizardOut = Join-Path $assets 'wizard-whale.bmp'
$wbmp.Save($wizardOut, [System.Drawing.Imaging.ImageFormat]::Bmp)
$wg.Dispose(); $wbmp.Dispose(); $wsrc.Dispose()
Write-Host "OK $wizardOut ($w x $h)"

# ---- whole-window background: eating-rice whale, very faded ----
$bw = 800; $bh = 600
$r2 = New-GradientCanvas $bw $bh
$bbmp = $r2[0]; $bg = $r2[1]
$bsrc = [System.Drawing.Image]::FromFile($BgPng)
Draw-Contain $bg $bsrc $bw $bh 0.30
$bgOut = Join-Path $assets 'wizard-bg.bmp'
$bbmp.Save($bgOut, [System.Drawing.Imaging.ImageFormat]::Bmp)
$bg.Dispose(); $bbmp.Dispose(); $bsrc.Dispose()
Write-Host "OK $bgOut ($bw x $bh)"

# ---- small image: solid background, no transparency ----
$sw = 55; $sh = 55
$small = New-Object System.Drawing.Bitmap($sw, $sh, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$sg = [System.Drawing.Graphics]::FromImage($small)
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.Clear($top)
$ssrc = [System.Drawing.Image]::FromFile($SmallPng)
$sg.DrawImage($ssrc, 0, 0, $sw, $sh)
$smallOut = Join-Path $assets 'wizard-small.bmp'
$small.Save($smallOut, [System.Drawing.Imaging.ImageFormat]::Bmp)
$sg.Dispose(); $small.Dispose(); $ssrc.Dispose()
Write-Host "OK $smallOut ($sw x $sh)"
