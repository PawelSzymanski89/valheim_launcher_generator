param(
    [string]$Text = "VLG",
    [string]$OutputPath = "assets/images/logo.png",
    [string]$FontPath = "assets/fonts/Norsebold.otf",
    [int]$Size = 256
)

Add-Type -AssemblyName System.Drawing

# Load custom font
$fontCollection = New-Object System.Drawing.Text.PrivateFontCollection
$fontCollection.AddFontFile((Resolve-Path $FontPath).Path)
$fontFamily = $fontCollection.Families[0]

# Create bitmap
$bmp = New-Object System.Drawing.Bitmap($Size, $Size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'HighQuality'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.InterpolationMode = 'HighQualityBicubic'

# Fill background with dark earthy tones (pixel-art style blocks)
$rand = New-Object System.Random(42)
$bgColors = @(
    [System.Drawing.Color]::FromArgb(255, 40, 30, 20),
    [System.Drawing.Color]::FromArgb(255, 60, 45, 30),
    [System.Drawing.Color]::FromArgb(255, 30, 40, 30),
    [System.Drawing.Color]::FromArgb(255, 20, 20, 20),
    [System.Drawing.Color]::FromArgb(255, 50, 35, 25)
)
$blockSize = 16
for ($y = 0; $y -lt $Size; $y += $blockSize) {
    for ($x = 0; $x -lt $Size; $x += $blockSize) {
        $color = $bgColors[$rand.Next($bgColors.Length)]
        $brush = New-Object System.Drawing.SolidBrush($color)
        $g.FillRectangle($brush, $x, $y, $blockSize, $blockSize)
        $brush.Dispose()
    }
}

# Draw gold border
$borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 180, 140, 60), 8)
$g.DrawRectangle($borderPen, 4, 4, $Size - 8, $Size - 8)
$borderPen.Dispose()

# Find the biggest font size that fills 99% of the height
$targetHeight = [int]($Size * 0.99)
$textFont = $null
$textSize = $null

# Binary search for optimal font size
$lo = 10
$hi = 400
while ($lo -le $hi) {
    $mid = [int](($lo + $hi) / 2)
    $testFont = New-Object System.Drawing.Font($fontFamily, $mid, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $measured = $g.MeasureString($Text, $testFont)
    if ($measured.Height -lt $targetHeight) {
        $lo = $mid + 1
        $textFont = $testFont
        $textSize = $measured
    } else {
        $hi = $mid - 1
        if ($measured.Height -le $targetHeight + 5) {
            $textFont = $testFont
            $textSize = $measured
        }
    }
}

# Draw text centered
$x = [int](($Size - $textSize.Width) / 2)
$y = [int](($Size - $textSize.Height) / 2)

# Shadow
$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
$g.DrawString($Text, $textFont, $shadowBrush, ($x + 3), ($y + 3))
$shadowBrush.Dispose()

# Main text (gold/white depending on context)
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 218, 165, 32))
$g.DrawString($Text, $textFont, $textBrush, $x, $y)
$textBrush.Dispose()
$g.Dispose()

# Save - handle both relative and absolute paths
if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $savePath = $OutputPath
} else {
    $savePath = Join-Path (Get-Location) $OutputPath
}
# Ensure directory exists
$saveDir = [System.IO.Path]::GetDirectoryName($savePath)
if (-not (Test-Path $saveDir)) { New-Item -ItemType Directory -Path $saveDir -Force | Out-Null }
$bmp.Save($savePath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$fontCollection.Dispose()

Write-Host "Icon generated: $OutputPath ($Text, font size: $($textFont.Size)px)"
