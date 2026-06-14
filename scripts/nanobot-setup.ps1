# nanobot-setup.ps1 - Nanobot Portable Setup Orchestrator (PowerShell 5.1+)
# powershell -NoProfile .\scripts\nanobot-setup.ps1

$ErrorActionPreference = "Stop"

$CallerScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot "init_portable.ps1") -MainScriptPath $CallerScript

# Start logging
$LogFile = Join-Path $ROOT "setup_log.txt"
Start-Transcript -Path $LogFile -Force -Append | Out-Null
Write-Host "[LOG] Setup log: $LogFile" -ForegroundColor Green

# -- Load helper functions -------------------------------------------
. (Join-Path $ROOT "scripts\setup\setup_helpers.ps1")

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$Host.UI.RawUI.WindowTitle = "Nanobot Portable - Setup"

$PY_DIR      = Join-Path $ROOT "bin"
$APP_DIR     = Join-Path $ROOT "app"
$SCRIPTS_DIR = Join-Path $ROOT "scripts"

$Is64    = [Environment]::Is64BitOperatingSystem
$ProcArch = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")

# Architecture-derived variables
$ArchPython      = if ($Is64) { "amd64" } else { "win32" }
$ArchNode        = if ($ProcArch -eq "ARM64") { "arm64" } elseif ($Is64) { "x64" } else { "x86" }
$ArchMinGit      = if ($Is64) { "64-bit" } else { "32-bit" }
$ArchGh          = if ($ProcArch -eq "ARM64") { "arm64" } elseif ($Is64) { "amd64" } else { "386" }
$MinGwDir        = if ($Is64) { "mingw64\bin" } else { "mingw32\bin" }

# Software version
$PyVer      = "3.12.0"
$GitVer     = "2.54.0"
$NodeVer    = "24.16.0"
$GhVer      = "2.93.0"

Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "       NANOBOT Portable Setup - Simata.id" -ForegroundColor Cyan
Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "  Folder: $ROOT"
Write-Host ""

if (Test-Path $LOCKHEAD) {
    Write-Host "  [lockhead] Setup was already completed before."
    Write-Host "  Delete file:  data\.lockhead"
    Write-Host "  then run again to re-setup."
    Write-Host ""
    Stop-Transcript | Out-Null
    exit 0
}

# ===== STEP 1: INTERNET =====
Write-Step "===== STEP 1: INTERNET CONNECTION ====="
try {
    $ping = Test-Connection -ComputerName "github.com" -Count 1 -Quiet -ErrorAction Stop
    if (-not $ping) { throw "No response" }
    Write-OK "Internet OK"
} catch {
    Write-Error "Cannot reach github.com"
    Stop-Transcript | Out-Null
    pause
    exit 1
}
Write-OK ""

# ===== STEP 2: DIRECTORIES =====
Write-Step "===== STEP 2: CREATE DIRECTORIES ====="
if (-not (Test-Path $PY_DIR))    { New-Item -ItemType Directory -Path $PY_DIR -Force | Out-Null }
if (-not (Test-Path $DATA_DIR))  { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }
$kd = Join-Path $DATA_DIR "knowledge"
if (-not (Test-Path $kd)) { New-Item -ItemType Directory -Path $kd -Force | Out-Null }
$ld = Join-Path $DATA_DIR "logs"
if (-not (Test-Path $ld)) { New-Item -ItemType Directory -Path $ld -Force | Out-Null }
if (-not (Test-Path $TMP_DIR))   { New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null }
$homeDir = Join-Path $ROOT "data\home"
if (-not (Test-Path $homeDir)) { New-Item -ItemType Directory -Path $homeDir -Force | Out-Null }
if (-not (Test-Path $SCRIPTS_DIR)) { New-Item -ItemType Directory -Path $SCRIPTS_DIR -Force | Out-Null }
Write-OK "OK"
Write-OK ""

# ===== STEP 2b: CHECK HELPERS =====
Write-Step "===== STEP 2b: CHECK HELPER SCRIPTS ====="
$dh = Join-Path $SCRIPTS_DIR "setup\download.ps1"
$eh = Join-Path $SCRIPTS_DIR "setup\extract.ps1"
if (-not (Test-Path $dh)) {
    Write-Error "$dh NOT FOUND!"
    Write-Info "Create those files first."
    Stop-Transcript | Out-Null
    pause
    exit 1
}
if (-not (Test-Path $eh)) {
    Write-Error "$eh NOT FOUND!"
    Write-Info "Create those files first."
    Stop-Transcript | Out-Null
    pause
    exit 1
}
try {
    $null = & powershell -ExecutionPolicy Bypass -NoProfile -Command "Write-Host 'PS OK'" 2>&1
} catch {
    Write-Error "PowerShell cannot run!"
    Stop-Transcript | Out-Null
    pause
    exit 1
}
Write-OK "OK"
Write-OK ""

# ===== INSTALL MODULES =====
try {
    . (Join-Path $SCRIPTS_DIR "setup\install_busybox.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_python.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_git.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_gh.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_nodejs.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_source.ps1")
    . (Join-Path $SCRIPTS_DIR "setup\install_deps.ps1")
} catch {
    Write-Host ""
Write-Host "  $('=' * 49)" -ForegroundColor Red
Write-Host "       SETUP FAILED! - Simata.id" -ForegroundColor Red
Write-Host "  $('=' * 49)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Stage: Check output above for failed step" -ForegroundColor Yellow
    Write-Host "  Full log: setup_log.txt" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Troubleshooting:" -ForegroundColor Cyan
    Write-Host "    - Check internet connection"
    Write-Host "    - Verify downloaded files in tmp/ folder"
    Write-Host "    - Re-run setup to retry"
    Write-Host ""
    Stop-Transcript | Out-Null
    pause
    exit 1
}

# ===== FINAL CLEANUP =====
Write-Info "Cleanup: removing tmp/ contents..."
Remove-Item -Path "$TMP_DIR\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$TMP_DIR\.*" -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "Cleanup done. app/ preserved."

# ===== VERIFICATION =====
Write-Header ""
Write-Header "  ==================================================="
Write-Header "               VERIFICATION!"
Write-Header "  ==================================================="
Write-Host ""

$BBExe = Join-Path $PY_DIR "busybox.exe"
Write-Host "  BusyBox: " -NoNewline
if (Test-Path $BBExe) { & $BBExe --help 2>&1 | Select-Object -First 1 } else { Write-Host "    [MISSING]" }

$PythonExe = Join-Path $PY_DIR "python.exe"
Write-Host "  Python: " -NoNewline
& $PythonExe --version 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "    [MISSING]" }

Write-Host "  pip: " -NoNewline
& $PythonExe -m pip --version 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "    [MISSING]" }

Write-Host "  Source code: " -NoNewline
if (Test-Path (Join-Path $APP_DIR "README.md")) { Write-OK "OK" } else { Write-Host "    [MISSING]" }

Write-Host "  Config: " -NoNewline
if (Test-Path (Join-Path $DATA_DIR "config.json")) { Write-OK "OK (config.json)" } else { Write-Host "    [MISSING] config.json" }

$EnvFile = Join-Path $DATA_DIR ".env"
Write-Host "  .env: " -NoNewline
if (Test-Path $EnvFile) { Write-OK "OK" } else { Write-Host "    [MISSING]" }
Write-Host ""

# ===== LOCKHEAD FALLBACK =====
if (-not (Test-Path $LOCKHEAD)) {
    & $PythonExe $LOCKHEAD_SCRIPT $ROOT
    Write-Info ".lockhead created."
}
Write-Info "    Please wait..."
Write-OK ""

# ===== HEALTH CHECK =====
Write-Header ""
Write-Header "  ==================================================="
Write-Header "               HEALTH CHECK"
Write-Header "  ==================================================="
Write-Host ""
Write-Info "Running system verification..."
$HealthScript = Join-Path $SCRIPTS_DIR "healthcheck.py"
if (Test-Path $HealthScript) {
    & $PythonExe $HealthScript
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Health check passed!"
    } else {
        Write-Warn "Health check reported warnings. Review output above."
    }
} else {
    Write-Warn "healthcheck.py not found, skipping."
}
Write-OK ""

# ===== FINISH SETUP =====
Write-Header ""
Write-Header "  ==================================================="
Write-Header "             SETUP COMPLETE!"
Write-Header "  ==================================================="
Write-Host ""
Write-Host "  NEXT STEPS:"
Write-Host "    1. Double-Click  edit_env.bat  to Add and Encrypt your API KEY"
Write-Host "    2. Double-Click  start-chat.bat  or  start-gateway.bat"
Write-Host ""
Write-Host "  Setup log saved: setup_log.txt" -ForegroundColor Green
Write-Host ""
Stop-Transcript | Out-Null
pause
