<#
.SYNOPSIS
  Builds all 3 modules as pre-compiled templates (ONE-TIME, requires Flutter SDK).
.DESCRIPTION
  After running this script, the generator no longer needs Flutter SDK.
  Templates are stored in templates/{launcher|patcher|updater}/
  and contain the full Release build with placeholder assets.
#>
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$ModulesDir = Join-Path $ProjectRoot 'lib\modules'
$TemplatesDir = Join-Path $ProjectRoot 'templates'

# Verify Flutter SDK
Write-Host "Checking Flutter SDK..." -ForegroundColor Cyan
$flutterCheck = flutter --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter SDK not found! Install it first." -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# ─── APP_SECRET from .env ───────────────────────────────────────────────────
$EnvFile = Join-Path $ProjectRoot '.env'
if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile -Raw
    $match = [regex]::Match($envContent, 'APP_SECRET=(.+)')
    if ($match.Success) {
        $AppSecret = $match.Groups[1].Value.Trim()
        Write-Host "APP_SECRET loaded from .env" -ForegroundColor Green
    } else {
        Write-Host ".env exists but APP_SECRET not found!" -ForegroundColor Red
        exit 1
    }
} else {
    # Auto-generate a cryptographically random secret
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $AppSecret = [Convert]::ToBase64String($bytes) -replace '[+/=]', 'x'
    $AppSecret = $AppSecret.Substring(0, [Math]::Min(40, $AppSecret.Length))
    "APP_SECRET=$AppSecret" | Set-Content $EnvFile -Encoding UTF8
    Write-Host "Generated new APP_SECRET and saved to .env" -ForegroundColor Yellow
    Write-Host "  IMPORTANT: Back up .env if you want to rebuild on another machine!" -ForegroundColor Yellow
}
Write-Host ""

# Module definitions
$modules = @(
    @{ Name = 'launcher'; Dir = 'launcher_module'; Exe = 'server_launcher'; Alias = 'l' },
    @{ Name = 'patcher';  Dir = 'patcher_module';  Exe = 'server_patcher';  Alias = 'p' },
    @{ Name = 'updater';  Dir = 'updater_module';  Exe = 'server_updater';  Alias = 'u' }
)

foreach ($mod in $modules) {
    $modPath = Join-Path $ModulesDir $mod.Dir
    $templateOut = Join-Path $TemplatesDir $mod.Name

    Write-Host "`nBuilding template: $($mod.Name)..." -ForegroundColor Cyan

    # Ensure placeholder assets exist (so Flutter bundles the asset paths)
    $assetsDir = Join-Path $modPath 'assets'
    
    # Write placeholder config_encrypted.json
    $configFile = Join-Path $assetsDir 'config_encrypted.json'
    if (-not (Test-Path $configFile) -or (Get-Item $configFile).Length -lt 10) {
        '{"data":"PLACEHOLDER_REPLACE_BY_GENERATOR"}' | Set-Content $configFile -Encoding UTF8
    }
    
    # Write placeholder manifest.sig
    $sigFile = Join-Path $assetsDir 'manifest.sig'
    if (-not (Test-Path $sigFile) -or (Get-Item $sigFile).Length -lt 5) {
        'PLACEHOLDER' | Set-Content $sigFile -Encoding UTF8
    }

    # For launcher: ensure video placeholder exists
    if ($mod.Name -eq 'launcher') {
        $videoDir = Join-Path $assetsDir 'video'
        New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
        $bgFile = Join-Path $videoDir 'background.mp4'
        if (-not (Test-Path $bgFile)) {
            # Create a tiny placeholder so Flutter registers the asset path
            [byte[]]$empty = @(0)
            [IO.File]::WriteAllBytes($bgFile, $empty)
        }
    }

    # Clean if requested
    if ($Clean) {
        Write-Host "  Cleaning..." -ForegroundColor Yellow
        Push-Location $modPath
        flutter clean
        Pop-Location
    }

    # Junction for short paths (Windows 260-char limit)
    $junctionPath = "C:\vlg\$($mod.Alias)"
    New-Item -ItemType Directory -Path 'C:\vlg' -Force -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $junctionPath) {
        cmd /c "rmdir `"$junctionPath`"" 2>$null
    }
    $mkResult = cmd /c "mklink /J `"$junctionPath`" `"$modPath`"" 2>&1
    $buildDir = if (Test-Path $junctionPath) { $junctionPath } else { $modPath }
    
    Write-Host "  flutter pub get..." -ForegroundColor Yellow
    Push-Location $modPath
    flutter pub get
    Pop-Location

    Write-Host "  flutter build windows --release --dart-define=APP_SECRET=***..." -ForegroundColor Yellow
    Push-Location $buildDir
    flutter build windows --release --dart-define="APP_SECRET=$AppSecret"
    $buildExit = $LASTEXITCODE
    Pop-Location

    # Remove junction
    if (Test-Path $junctionPath) {
        cmd /c "rmdir `"$junctionPath`"" 2>$null
    }

    if ($buildExit -ne 0) {
        Write-Host "  BUILD FAILED for $($mod.Name)!" -ForegroundColor Red
        exit 1
    }

    # Copy Release folder to templates/
    $releaseDir = Join-Path $modPath 'build\windows\x64\runner\Release'
    if (-not (Test-Path $releaseDir)) {
        Write-Host "  Release dir not found: $releaseDir" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Copying to templates/$($mod.Name)/..." -ForegroundColor Yellow
    if (Test-Path $templateOut) {
        Remove-Item $templateOut -Recurse -Force
    }
    Copy-Item $releaseDir -Destination $templateOut -Recurse -Force

    $exeFile = Join-Path $templateOut "$($mod.Exe).exe"
    if (Test-Path $exeFile) {
        $exeSize = [math]::Round((Get-Item $exeFile).Length / 1MB, 1)
        Write-Host "  OK: $($mod.Exe).exe ($exeSize MB)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: $($mod.Exe).exe not found in template!" -ForegroundColor Yellow
    }
}

Write-Host "`n=== All templates built ===" -ForegroundColor Green
Write-Host "Templates location: $TemplatesDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "The generator no longer needs Flutter SDK." -ForegroundColor Green
Write-Host "It will copy templates and inject assets at generation time." -ForegroundColor Green
