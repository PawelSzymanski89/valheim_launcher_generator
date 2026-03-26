<#
.SYNOPSIS
  Builds the Valheim Launcher Generator and packages it as a self-contained ZIP.
.DESCRIPTION
  1. Builds the generator Flutter app (flutter build windows)
  2. Copies tools/ffmpeg.exe alongside the built exe
  3. Creates ValheimLauncherGenerator_v{VERSION}.zip
#>
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Read version from pubspec.yaml
$pubspec = Get-Content (Join-Path $ProjectRoot 'pubspec.yaml') -Raw
$version = [regex]::Match($pubspec, 'version:\s*(\S+)').Groups[1].Value
Write-Host "Generator version: $version" -ForegroundColor Cyan

$ReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$OutputZip = Join-Path $ProjectRoot "ValheimLauncherGenerator_v$version.zip"

# 1. Build
if (-not $SkipBuild) {
    Write-Host "Building generator (flutter build windows)..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
    Write-Host "Build complete." -ForegroundColor Green
}

if (-not (Test-Path $ReleaseDir)) {
    Write-Host "Release directory not found: $ReleaseDir" -ForegroundColor Red
    exit 1
}

# 2. Copy bundled tools (ffmpeg.exe)
$FfmpegSrc = Join-Path $ProjectRoot 'tools\ffmpeg.exe'
$FfmpegDest = Join-Path $ReleaseDir 'tools'
if (Test-Path $FfmpegSrc) {
    New-Item -ItemType Directory -Path $FfmpegDest -Force | Out-Null
    Copy-Item $FfmpegSrc -Destination (Join-Path $FfmpegDest 'ffmpeg.exe') -Force
    Write-Host "Bundled tools/ffmpeg.exe into release." -ForegroundColor Green
} else {
    Write-Host "WARNING: tools/ffmpeg.exe not found. Run download_ffmpeg.ps1 first!" -ForegroundColor Yellow
}

# 3. Ensure modules source is included (generator needs them for building)
# The modules are in lib/modules/ and are part of the Flutter assets/data
# They should already be included by flutter build

# 4. Package as ZIP
Write-Host "Creating $OutputZip..." -ForegroundColor Yellow
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }

# Create a temp staging folder with a clean name
$StagingDir = Join-Path $env:TEMP "ValheimLauncherGenerator_v$version"
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

# Copy release contents
Copy-Item "$ReleaseDir\*" -Destination $StagingDir -Recurse -Force

# Copy required source directories that generator needs at runtime:
# - templates/ (pre-compiled modules for instant generation)
# - scripts/ (icon generation, etc.)
# - assets/ (fonts, images)
$RuntimeDirs = @('templates', 'scripts', 'assets', 'profiles')
foreach ($dir in $RuntimeDirs) {
    if (Test-Path $dir) {
        $dest = Join-Path $StagingDir $dir
        Copy-Item $dir -Destination $dest -Recurse -Force
    }
}

# Copy pubspec.yaml (needed for version detection)
Copy-Item (Join-Path $ProjectRoot 'pubspec.yaml') -Destination $StagingDir -Force

Compress-Archive -Path "$StagingDir\*" -DestinationPath $OutputZip -Force

# Cleanup staging
Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue

$zipSize = [math]::Round((Get-Item $OutputZip).Length / 1MB, 1)
Write-Host "Done! $OutputZip ($zipSize MB)" -ForegroundColor Green
