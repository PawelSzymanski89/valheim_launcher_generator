<#
.SYNOPSIS
  Downloads ffmpeg essentials build and extracts ffmpeg.exe to tools/
#>

# Resolve project root (script is in scripts/ subfolder)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$ToolsDir = Join-Path $ProjectRoot 'tools'
$FfmpegExe = Join-Path $ToolsDir 'ffmpeg.exe'

# Check if already downloaded
if (Test-Path $FfmpegExe) {
    $size = [math]::Round((Get-Item $FfmpegExe).Length / 1MB, 1)
    Write-Host "ffmpeg.exe already exists ($size MB)" -ForegroundColor Green
    exit 0
}

Write-Host "Downloading ffmpeg essentials..." -ForegroundColor Cyan

# Create tools directory
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null

$Url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$ZipPath = Join-Path $env:TEMP 'ffmpeg-essentials.zip'
$ExtractPath = Join-Path $env:TEMP 'ffmpeg-extract'

try {
    Write-Host "  Downloading from gyan.dev..." -ForegroundColor Yellow
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
    $dlSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
    Write-Host "  Downloaded: $dlSize MB" -ForegroundColor Green

    Write-Host "  Extracting ffmpeg.exe..." -ForegroundColor Yellow
    if (Test-Path $ExtractPath) {
        Remove-Item $ExtractPath -Recurse -Force
    }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force

    # Find ffmpeg.exe in bin/ subfolder
    $found = Get-ChildItem -Path $ExtractPath -Recurse -Filter 'ffmpeg.exe' |
        Where-Object { $_.Directory.Name -eq 'bin' } |
        Select-Object -First 1

    if (-not $found) {
        Write-Host "  ffmpeg.exe not found in archive!" -ForegroundColor Red
        exit 1
    }

    Copy-Item $found.FullName -Destination $FfmpegExe -Force
    $exeSize = [math]::Round((Get-Item $FfmpegExe).Length / 1MB, 1)
    Write-Host "  ffmpeg.exe copied to tools/ ($exeSize MB)" -ForegroundColor Green
}
catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $ExtractPath) {
        Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "ffmpeg bundled successfully!" -ForegroundColor Green
