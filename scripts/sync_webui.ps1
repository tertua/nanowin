# sync_webui.ps1 - Copy manually-built webui from data\webui\ to installed package
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File sync_webui.ps1
#        or run sync-webui.bat wrapper.
#
# Why: Lite sets $env:NANOBOT_SKIP_WEBUI_BUILD=1 in install_deps.ps1, so the
# upstream hatch hook never builds nanobot\web\dist\. The gateway checks
# bin\Lib\site-packages\nanobot\web\dist\ at startup; if absent, no webui.
#
# Idempotent: skips if drop zone is older than installed copy.
# Re-run after every setup.bat (Lite's pip install will not preserve webui)
# or after editing data\webui\.

$ErrorActionPreference = 'Stop'

$CallerScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot "init_portable.ps1") -MainScriptPath $CallerScript

# -- Manual fallback if init_portable.ps1 didn't set $ROOT ------------------
if (-not $ROOT) { $ROOT = Split-Path -Parent $PSScriptRoot }

# -- Portable env vars -----------------------------------------------------
$DropDir  = Join-Path $DATA_DIR "webui"
if (-not (Test-Path $PY)) {
    Write-Host "[ERROR] Python not found: $PY" -ForegroundColor Red
    Write-Host "         Run setup.bat first." -ForegroundColor Red
    exit 1
}

$SitePkgs = Join-Path $ROOT "bin\Lib\site-packages"
if (-not (Test-Path $SitePkgs)) {
    Write-Host "[ERROR] site-packages not found: $SitePkgs" -ForegroundColor Red
    Write-Host "         Re-run setup.bat to install Python + nanobot." -ForegroundColor Red
    exit 1
}

$WebPkgInit = Join-Path $SitePkgs "nanobot\web\__init__.py"
$DistDir    = Join-Path $SitePkgs "nanobot\web\dist"

if (-not (Test-Path $WebPkgInit)) {
    Write-Host "[ERROR] nanobot not installed at $SitePkgs\nanobot\web" -ForegroundColor Red
    Write-Host "         Run setup.bat first." -ForegroundColor Red
    exit 1
}

# -- Validate drop zone ----------------------------------------------------
if (-not (Test-Path $DropDir)) {
    Write-Host "[ERROR] Drop zone empty: $DropDir" -ForegroundColor Red
    Write-Host "         Build webui first: cd app\webui && npm install && npm run build" -ForegroundColor Red
    Write-Host "         Then copy the dist/ contents into $DropDir" -ForegroundColor Red
    exit 1
}

$DropIndex = Join-Path $DropDir "index.html"
if (-not (Test-Path $DropIndex)) {
    Write-Host "[WARN] Drop zone exists but missing index.html: $DropDir" -ForegroundColor Yellow
    Write-Host "       Upstream will not serve webui without index.html." -ForegroundColor Yellow
}

# -- Idempotent: skip if installed dist is newer than drop zone ------------
$DistIndex = Join-Path $DistDir "index.html"
if ((Test-Path $DistIndex)) {
    try {
        $DropMtime = (Get-Item $DropIndex).LastWriteTime
        $DistMtime = (Get-Item $DistIndex).LastWriteTime
        if ($DistMtime -ge $DropMtime) {
            Write-Host "[OK] Installed webui is up-to-date (no sync needed)." -ForegroundColor Green
            Write-Host "     Source: $DropDir  (mtime: $DropMtime)"
            Write-Host "     Target: $DistDir  (mtime: $DistMtime)"
            exit 0
        }
    } catch {
        # mtime comparison failed; fall through to copy
    }
}

# -- Ensure target dir exists ----------------------------------------------
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

# -- Copy ------------------------------------------------------------------
try {
    Copy-Item -Path (Join-Path $DropDir "*") -Destination $DistDir -Recurse -Force
} catch {
    Write-Host "[ERROR] Copy failed: $_" -ForegroundColor Red
    exit 1
}

# -- Stats -----------------------------------------------------------------
$fileCount = (Get-ChildItem -Path $DistDir -Recurse -File).Count
$totalSize = (Get-ChildItem -Path $DistDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$sizeKb = "{0:N1}" -f ($totalSize / 1KB)

Write-Host "[OK] Webui synced." -ForegroundColor Green
Write-Host "     Source: $DropDir"
Write-Host "     Target: $DistDir"
Write-Host "     Files : $fileCount"
Write-Host "     Size  : $sizeKb KB"
Write-Host ""
Write-Host "Next: run start-gateway.bat" -ForegroundColor Cyan
