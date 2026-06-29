# Baroudeur Studio - Clean Build Script
# Ce script nettoie le projet et relance un build propre

param (
    [switch]$SkipPubGet,
    [switch]$DebugBuild,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\clean_build.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -SkipPubGet    : Saute l'execution de 'flutter pub get'"
    Write-Host "  -DebugBuild    : Fait un build debug au lieu de release"
    Write-Host "  -Help          : Affiche cette aide"
    Write-Host ""
    Write-Host "Exemples:"
    Write-Host "  .\clean_build.ps1                 # Build release complet"
    Write-Host "  .\clean_build.ps1 -DebugBuild    # Build debug"
    Write-Host "  .\clean_build.ps1 -SkipPubGet    # Sans pub get"
    exit 0
}

Write-Host "=== Baroudeur Studio - Nettoyage et Build ===" -ForegroundColor Cyan
Write-Host ""

# Etape 1: Tuer les processus qui pourraient bloquer les fichiers
Write-Host "[1/5] Fermeture des processus Gradle/Dart..." -ForegroundColor Yellow
Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "dart" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "gradle*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Etape 2: Nettoyage des dossiers
Write-Host "[2/5] Nettoyage des dossiers build et .gradle..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Path "build" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  - Dossier 'build' supprime" -ForegroundColor Green
}

if (Test-Path ".gradle") {
    Remove-Item -Path ".gradle" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  - Dossier '.gradle' supprime" -ForegroundColor Green
}

# Etape 3: flutter clean
Write-Host "[3/5] Execution de 'flutter clean'..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "  - ERREUR: flutter clean a echoue" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Etape 4: flutter pub get (sauf si -SkipPubGet)
if (-not $SkipPubGet) {
    Write-Host "[4/5] Execution de 'flutter pub get'..." -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  - ERREUR: flutter pub get a echoue" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# Etape 5: Build
Write-Host "[5/5] Build Flutter..." -ForegroundColor Yellow
if ($DebugBuild) {
    Write-Host "  - Mode: DEBUG" -ForegroundColor Cyan
    flutter build apk --debug
} else {
    Write-Host "  - Mode: RELEASE" -ForegroundColor Cyan
    flutter build apk --release
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== BUILD REUSSI ===" -ForegroundColor Green
    if ($DebugBuild) {
        Write-Host "APK generé: build/app/outputs/flutter-apk/app-debug.apk" -ForegroundColor Green
    } else {
        Write-Host "APK generé: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "=== BUILD ECHOUE ===" -ForegroundColor Red
    exit $LASTEXITCODE
}
