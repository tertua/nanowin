# nanobot-agent.ps1 - Nanobot Portable CLI Chat (PowerShell 5.1+)
# Place this script at the Nanobot root directory (\nanobot-usb\)

$ErrorActionPreference = 'Stop'

$CallerScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot "init_portable.ps1") -MainScriptPath $CallerScript

# -- UTF-8 output ----------------------------------------------------
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

# -- Paths -----------------------------------------------------------
$CONFIG    = Join-Path $DATA_DIR "config.json"
$WORKSPACE = Join-Path $DATA_DIR "workspace"

# -- Check Python ----------------------------------------------------
if (-not (Test-Path $PY)) {
    Write-Host "`n  [ERROR] Python not found: $PY" -ForegroundColor Red
    Write-Host "  Setup incomplete.`n" -ForegroundColor Red
    exit 1
}

# -- Check Config ----------------------------------------------------
if (-not (Test-Path $CONFIG)) {
    Write-Host "`n  [ERROR] Config not found: $CONFIG" -ForegroundColor Red
    Write-Host "  Run setup.bat or copy config first.`n" -ForegroundColor Red
    exit 1
}

# -- Banner ----------------------------------------------------------
Write-Host "`n"
Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "       NANOBOT PORTABLE - Simata.id" -ForegroundColor Cyan
Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "`n"

# -- Load .env (AES-GCM scrypt) --------------------------------------
if (-not (Load-EnvEncrypted -Root $ROOT -DataDir $DATA_DIR -Python $PY)) {
    Write-Host "`n  [ERROR] Failed to decrypt .env.encrypted" -ForegroundColor Red
    Write-Host "  Run edit_env.bat to set up your API key.`n" -ForegroundColor Red
    exit 1
}

# -- Resolve workspace from config.json ------------------------------
try {
    $resolved = Resolve-Workspace -ConfigPath $CONFIG
    if ($resolved) { $WORKSPACE = $resolved }
} catch {
    # fallback: keep default WORKSPACE
}

# -- Info ------------------------------------------------------------
Write-Host "  $('=' * 47)" -ForegroundColor Cyan
Write-Host "`n"
Write-Host "  Home  : $NANOBOT_HOME" -ForegroundColor Green
Write-Host "  Conf  : $CONFIG" -ForegroundColor Green
Write-Host "  Works : $WORKSPACE" -ForegroundColor Green
Write-Host "`n"
Write-Host "  $('=' * 47)" -ForegroundColor Cyan
Write-Host "`n  Type your command, Press ESC+ENTER`n" -ForegroundColor Yellow

# -- Run Agent -------------------------------------------------------
try {
    & $PY -m nanobot agent "--config=$CONFIG"
    $exitCode = $LASTEXITCODE
} catch {
    Write-Host "`n  [ERROR] Agent crashed: $_" -ForegroundColor Red
    $exitCode = 1
}

Write-Host "`n  Chat session ended (exit code: $exitCode)" -ForegroundColor Gray

if ($exitCode -ne 0) {
    Write-Host "`n  Press Enter to exit..." -NoNewline
    $null = Read-Host
}
