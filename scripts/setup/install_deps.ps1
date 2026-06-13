# install_deps.ps1 - Dependencies and configuration module
# Usage: . (Join-Path $SCRIPTS_DIR "install_deps.ps1")

# ===== STEP 6: DEPENDENCIES =====
Write-Step "===== STEP 6: INSTALL DEPENDENCIES ====="
Write-Step "         [API ONLY MODE]"
Write-Info "Install lightweight dependencies..."
Write-OK ""

$ReqFile = Join-Path $SCRIPTS_DIR "requirements-lite.txt"
if (-not (Test-Path $ReqFile)) {
    Write-Error "requirements-lite.txt not found: $ReqFile"
    pause
    exit 1
}
Write-Info "Installing packages from requirements-lite.txt ..."
& $PythonExe -m pip install --no-warn-script-location --upgrade pip setuptools wheel hatchling hatch-vcs -r $ReqFile
Write-OK ""

Write-Info "Build nanobot core..."
$env:NANOBOT_SKIP_WEBUI_BUILD = "1"
$PyProject = Join-Path $APP_DIR "pyproject.toml"
if (Test-Path $PyProject) {
    & $PythonExe -m pip install --no-warn-script-location --no-deps $APP_DIR
} elseif (Test-Path $APP_DIR) {
    Write-Info "Adding app to PYTHONPATH..."
}
Write-OK ""

Write-OK ""
Write-Header "  ----------------------------------------"
Write-Header "  Installed packages:"
& $PythonExe -m pip list 2>$null
Write-Header "  ----------------------------------------"
Write-OK ""

# ===== STEP 7: CONFIGURATION =====
Write-Step "===== STEP 7: GENERATE CONFIGURATION ====="
$ConfigFile = Join-Path $DATA_DIR "config.json"
$WorkspaceDir = "data/workspace"
if (Test-Path $ConfigFile) {
    Write-Info "config.json already exists. Skipping."
} else {
    Write-Info "Generate config via nanobot onboard..."
    & $PythonExe -m nanobot onboard "--config=$ConfigFile" "--workspace=$WorkspaceDir"
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Failed to generate config.json!"
        pause
        exit 1
    }
    Write-Info "Post-process config for portable..."
    & $PythonExe (Join-Path $SCRIPTS_DIR "post_config.py") $ConfigFile $ROOT
}
Write-OK "config.json ready."

& $PythonExe $LOCKHEAD_SCRIPT $ROOT
Write-OK "lockhead installed."

$EnvFile = Join-Path $DATA_DIR ".env"
$EnvEnc  = Join-Path $DATA_DIR ".env.encrypted"
if (Test-Path $EnvEnc) {
    Write-OK ".env.encrypted exists; .env not needed."
} elseif (Test-Path $EnvFile) {
    Write-OK ".env ready (synced by post_config.py from config.json)."
} else {
    Write-Warn ".env missing after post_config. Creating minimal placeholder."
    Set-Content -Path $EnvFile -Value @(
        "# .env placeholder. Run setup.bat again to sync from config.json."
    ) -Encoding Ascii
}
Write-OK ""
