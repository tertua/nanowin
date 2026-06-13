# ==========================================================
#  nanobot-gateway.ps1 - NanoBot Gateway Runtime
# ==========================================================

$ErrorActionPreference = 'Stop'

$CallerScript = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot "init_portable.ps1") -MainScriptPath $CallerScript

# -- UTF-8 output ----------------------------------------------------
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

# -- Paths -----------------------------------------------------------
$CONFIG    = Join-Path $DATA_DIR "config.json"
$WORKSPACE = Join-Path $DATA_DIR "workspace"

# -- Read ports from config.json --------------------------------------
$HTTP_PORT = $null
$WS_PORT   = $null
try {
    $cfg = Get-Content -Path $CONFIG -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.api -and $cfg.api.port)                       { $HTTP_PORT = [int]$cfg.api.port }
    if ($cfg.channels.websocket -and $cfg.channels.websocket.port) { $WS_PORT   = [int]$cfg.channels.websocket.port }
} catch {
    Write-Warning "Could not read ports from $CONFIG : $($_.Exception.Message). Using defaults."
}

if (-not $HTTP_PORT) { $HTTP_PORT = 8900 }
if (-not $WS_PORT)   { $WS_PORT   = 8765 }

$WS_HOST = "127.0.0.1"

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

# -- Port cleanup ----------------------------------------------------
function Stop-ProcessOnPort {
    param([Parameter(Mandatory=$true)][int]$Port)
    try {
        $lines = netstat -ano | Select-String ":$Port " | Select-String "LISTENING"
        if ($lines) {
            $lines | ForEach-Object {
                if ($_ -match '\s+(\d+)$') {
                    Stop-Process -Id ([int]$matches[1]) -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }
}

function Stop-GatewayProcess {
    Stop-ProcessOnPort -Port $HTTP_PORT
    Stop-ProcessOnPort -Port $WS_PORT
}

# Defensive: if PowerShell exits mid-run (e.g. user kills the window),
# release the ports so the next launch doesn't have to fight a TIME_WAIT.
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Stop-GatewayProcess } | Out-Null

# -- Kill any stale processes on target ports -----------------------
Stop-GatewayProcess

# -- Banner ----------------------------------------------------------
Write-Host "`n"
Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "       NANOBOT GATEWAY" -ForegroundColor Cyan
Write-Host "  $('=' * 49)" -ForegroundColor Cyan
Write-Host "`n"

Write-Host "  Home  : $NANOBOT_HOME" -ForegroundColor Green
Write-Host "  Conf  : $CONFIG" -ForegroundColor Green
Write-Host "  Works : $WORKSPACE" -ForegroundColor Green
Write-Host "`n"
Write-Host "  Host  : $WS_HOST" -ForegroundColor Green
Write-Host "  HTTP  : $HTTP_PORT" -ForegroundColor Green
Write-Host "  WS    : $WS_PORT" -ForegroundColor Green
Write-Host "  $('=' * 47)" -ForegroundColor Cyan
Write-Host "`n  Please wait..." -ForegroundColor Yellow

# -- Resolve workspace from config.json ------------------------------
try {
    $resolved = Resolve-Workspace -ConfigPath $CONFIG
    if ($resolved) { $WORKSPACE = $resolved }
} catch {
    # fallback: keep default WORKSPACE
}

# -- Load .env (AES-GCM scrypt) --------------------------------------
Load-EnvEncrypted -Root $ROOT -DataDir $DATA_DIR -Python $PY

# -- Browser URL -----------------------------------------------------
Write-Host "`n"
Write-Host "  Browser: http://$WS_HOST`:$WS_PORT" -ForegroundColor Green
Write-Host "`n"

Write-Host "  HTTP Port : $HTTP_PORT (for Health/API)" -ForegroundColor Gray
Write-Host "  WS Port   : $WS_PORT (for WebSocket/UI)" -ForegroundColor Gray
Write-Host "`n"

# -- Run Gateway ------------------------------------------------------
try {
    & $PY -m nanobot gateway `
        "--config=$CONFIG" `
        "--port=$HTTP_PORT"
    $exitCode = $LASTEXITCODE
} catch {
    Write-Host "`n  [ERROR] Gateway crashed: $_" -ForegroundColor Red
    $exitCode = 1
}

if ($exitCode -eq 0) {
    Write-Host "  Nanobot Gateway Stopped." -ForegroundColor Cyan
} else {
    Write-Host "  Nanobot Gateway stopped with error code: $exitCode" -ForegroundColor Red
}
Write-Host "`n"

exit $exitCode
