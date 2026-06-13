# init_portable.ps1 - Portable environment initialization (shared)
# Dot-source this from all main .ps1 scripts
# Usage: . (Join-Path $PSScriptRoot "init_portable.ps1") [-MainScriptPath <path>]

param(
    [string]$MainScriptPath = ""
)

# -- Execution policy handler ----------------------------------------
if ($MainScriptPath) {
    $currentPolicy = Get-ExecutionPolicy
    if ($currentPolicy -match 'Restricted|AllSigned') {
        $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        Write-Host "Relaunching with execution policy bypass..." -ForegroundColor Yellow
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $MainScriptPath
        exit $LASTEXITCODE
    }
}

# -- Root directory = scripts/ parent --------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ROOT = Split-Path $ScriptDir -Parent
Set-Location $ROOT

# -- Common portable paths -------------------------------------------
$DATA_DIR = Join-Path $ROOT "data"
$HOME_DIR = Join-Path $DATA_DIR "home"
$TMP_DIR  = Join-Path $ROOT "tmp"
$NANOBOT_HOME = $DATA_DIR
$PY = Join-Path $ROOT "bin\python.exe"
$LOCKHEAD = Join-Path $DATA_DIR ".lockhead"
$LOCKHEAD_SCRIPT = Join-Path $ROOT "scripts\lockhead.py"

# -- Redirect environment variables to portable locations -------------
$Env:USERPROFILE      = $HOME_DIR
$Env:HOME             = $HOME_DIR
$Env:HOMEPATH         = $HOME_DIR
$Env:LOCALAPPDATA     = Join-Path $HOME_DIR "AppData\Local"
$Env:APPDATA          = Join-Path $HOME_DIR "AppData\Roaming"
$Env:TMP              = $TMP_DIR
$Env:TEMP             = $TMP_DIR
$Env:NANOBOT_HOME     = $DATA_DIR
$Env:GH_CONFIG_DIR    = $APPDATA

# -- Python/Node.js cache paths ---------------------------------------
$Env:PIP_CACHE_DIR    = Join-Path $TMP_DIR "pip-cache"
$Env:NPM_CONFIG_CACHE = Join-Path $TMP_DIR "npm-cache"
$Env:NPM_CONFIG_PREFIX = Join-Path $ROOT "bin\nodejs\global"

# -- Portable PATH entries (shared by all launchers) ------------------
$PortablePaths = @(
    Join-Path $ROOT "bin"
    Join-Path $ROOT "bin\Scripts"
    Join-Path $ROOT "bin\gh\bin"
    Join-Path $ROOT "bin\nodejs"
    Join-Path $ROOT "bin\git\cmd"
    Join-Path $ROOT "bin\git\mingw64\bin"
    Join-Path $ROOT "scripts"
    $DATA_DIR
)

# -- Inject portable PATH -------------------------------------------
$env:PATH = ($PortablePaths -join ';') + ';' + $env:PATH

# -- Create portable directories if missing ---------------------------
if (-not (Test-Path $HOME_DIR)) {
    New-Item -ItemType Directory -Path $HOME_DIR -Force | Out-Null
}
if (-not (Test-Path (Join-Path $HOME_DIR "AppData\Local"))) {
    New-Item -ItemType Directory -Path (Join-Path $HOME_DIR "AppData\Local") -Force | Out-Null
}
if (-not (Test-Path (Join-Path $HOME_DIR "AppData\Roaming"))) {
    New-Item -ItemType Directory -Path (Join-Path $HOME_DIR "AppData\Roaming") -Force | Out-Null
}
if (-not (Test-Path $TMP_DIR)) {
    New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null
}

# -- Function: Resolve-Workspace from config.json --------------------
function Resolve-Workspace {
    param([string]$ConfigPath = (Join-Path $DATA_DIR "config.json"))
    $script = Join-Path $ROOT "scripts\resolve_workspace.py"
    if (Test-Path $script -and (Test-Path $PY)) {
        $raw = & $PY $script $ConfigPath $ROOT 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            return $raw.Trim()
        }
    }
    return $null
}

# -- Internal: parse lines into env vars -----------------------------
function _Set-EnvFromLines {
    param([string[]]$Lines)
    $Lines | ForEach-Object {
        $idx = $_.IndexOf('=')
        if ($idx -gt 0) {
            [Environment]::SetEnvironmentVariable($_.Substring(0,$idx).Trim(), $_.Substring($idx+1).Trim(), 'Process')
        }
    }
}

# -- Function: Load-EnvEncrypted (AES-GCM scrypt) --------------------
function Load-EnvEncrypted {
    param(
        [string]$Root = $ROOT,
        [string]$DataDir = $DATA_DIR,
        [string]$Python = $PY
    )

    $EnvFileEnc = Join-Path $DataDir ".env.encrypted"
    $EnvKeyFile = Join-Path $DataDir ".env_key"
    $EnvTmpFile = Join-Path $DataDir ".env.tmp"
    $EnvPlain   = Join-Path $DataDir ".env"

    if (Test-Path $EnvFileEnc) {
        if (Test-Path $EnvKeyFile) {
            $env:NANOBOT_ENV_KEY = (Get-Content -Path $EnvKeyFile -TotalCount 1).Trim()
            & $Python (Join-Path $Root "scripts\env_crypt.py") load --noninteractive
        } else {
            & $Python (Join-Path $Root "scripts\env_crypt.py") load
        }
        if (Test-Path $EnvTmpFile) {
            _Set-EnvFromLines (Get-Content -Path $EnvTmpFile)
            Remove-Item -Path $EnvTmpFile -Force
        }
    } elseif (Test-Path $EnvPlain) {
        _Set-EnvFromLines (Get-Content -Path $EnvPlain)
    }
}
