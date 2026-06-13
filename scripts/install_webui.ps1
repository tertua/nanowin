# install_webui.ps1 - Build upstream webui and sync to installed package
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install_webui.ps1
#        or run build-webui.bat
#
# Why: Lite sets NANOBOT_SKIP_WEBUI_BUILD=1 in install_deps.ps1, so the upstream
# hatch hook never builds nanobot\web\dist\. This script is the manual
# equivalent: run npm install + build, then call sync_webui.ps1 to push the
# build into bin\Lib\site-packages\nanobot\web\dist\.
#
# Runner: npm only. Lite redirects HOME/USERPROFILE to the USB via
# init_portable.ps1, which makes bun's HOME-relative package store
# (~/.bun/install/cache) land on exFAT/FAT32 where MoveFileEx returns EINVAL.
# Bun's --no-cache flag only skips the manifest cache, not the package store,
# and there is no env var to override the cache dir. npm's flat node_modules
# writes work on every filesystem, so npm is the only path that is truly
# portable. Bun is not used here.
#
# Failure: exits 1 with clear error. setup.bat is unaffected (this is a
# separate, manual step). User can re-run build-webui.bat to retry.
#
# Idempotent: npm install is incremental (skips already-installed packages).
# node_modules persists across runs.

$ErrorActionPreference = 'Stop'

$CallerScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot "init_portable.ps1") -MainScriptPath $CallerScript

# -- Paths ------------------------------------------------------------------
$WebuiDir  = Join-Path $ROOT "app\webui"
$WebPkgJson = Join-Path $WebuiDir "package.json"
$BuildOut  = Join-Path $ROOT "app\nanobot\web\dist"
$IndexOut  = Join-Path $BuildOut "index.html"

# -- Pre-flight: source must be cloned --------------------------------------
if (-not (Test-Path $WebPkgJson)) {
    Write-Host "[ERROR] app\webui\package.json not found." -ForegroundColor Red
    Write-Host "         Lite ZIP install does not include webui source." -ForegroundColor Red
    Write-Host "         Run setup.bat (clones from git) before build-webui.bat." -ForegroundColor Red
    exit 1
}

# -- Resolve npm ------------------------------------------------------------
# Try portable npm at bin\nodejs\npm.cmd (Lite's standard location, set up
# by setup.bat). Fall back to system npm if portable not found. Direct path
# lookup — does not depend on $env:PATH being set by the caller.
$npmPath = $null
$portableNpm = Join-Path $ROOT "bin\nodejs\npm.cmd"
if (Test-Path $portableNpm) {
    $npmPath = $portableNpm
} else {
    $sysNpm = Get-Command "npm" -ErrorAction SilentlyContinue
    if ($sysNpm) { $npmPath = $sysNpm.Source }
}
if (-not $npmPath) {
    Write-Host "[ERROR] npm not found." -ForegroundColor Red
    Write-Host "         Expected portable: $portableNpm" -ForegroundColor Red
    Write-Host "         Or system npm in PATH." -ForegroundColor Red
    Write-Host "         Re-run setup.bat to install Node.js into bin\." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Runner: npm" -ForegroundColor Green
Write-Host "     Path:  $npmPath"

# -- Run install ------------------------------------------------------------
Write-Host ""
Write-Host "[INFO] Running 'npm install' in app\webui..." -ForegroundColor Cyan
Write-Host "       (first run may take several minutes for ~250MB node_modules)"
Push-Location $WebuiDir
try {
    & $npmPath install
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Host "[ERROR] npm install failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
} catch {
    Pop-Location
    Write-Host "[ERROR] npm install exception: $_" -ForegroundColor Red
    exit 1
}

# -- Run build --------------------------------------------------------------
Write-Host ""
Write-Host "[INFO] Running 'npm run build' in app\webui..." -ForegroundColor Cyan
try {
    & $npmPath run build
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Host "[ERROR] npm run build failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
} catch {
    Pop-Location
    Write-Host "[ERROR] npm run build exception: $_" -ForegroundColor Red
    exit 1
}
Pop-Location

# -- Verify build output ----------------------------------------------------
if (-not (Test-Path $IndexOut)) {
    Write-Host "[ERROR] Build succeeded but $IndexOut is missing." -ForegroundColor Red
    Write-Host "         Check app\webui\vite.config.ts (outDir)." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Build output: $BuildOut" -ForegroundColor Green

# -- Copy build to installed package ----------------------------------------
# Direct copy: build output (app\nanobot\web\dist) -> site-packages.
# Do NOT call sync_webui.ps1 here — that script reads from data\webui\
# (manual drop-zone workflow) and would either fail or copy stale files.
$SitePkgs = Join-Path $ROOT "bin\Lib\site-packages"
$SiteDist = Join-Path $SitePkgs "nanobot\web\dist"
if (-not (Test-Path $SitePkgs)) {
    Write-Host "[ERROR] site-packages not found: $SitePkgs" -ForegroundColor Red
    Write-Host "         Re-run setup.bat to install Python + nanobot." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $SiteDist)) {
    New-Item -ItemType Directory -Path $SiteDist -Force | Out-Null
}
try {
    Copy-Item -Path (Join-Path $BuildOut "*") -Destination $SiteDist -Recurse -Force
} catch {
    Write-Host "[ERROR] Copy to site-packages failed: $_" -ForegroundColor Red
    exit 1
}

$fileCount = (Get-ChildItem -Path $SiteDist -Recurse -File).Count

Write-Host ""
Write-Host "[OK] Webui build + sync complete." -ForegroundColor Green
Write-Host "     Build:   $BuildOut" -ForegroundColor Cyan
Write-Host "     Installed: $SiteDist" -ForegroundColor Cyan
Write-Host "     Files:   $fileCount" -ForegroundColor Cyan
Write-Host "     Next: run start-gateway.bat" -ForegroundColor Cyan
