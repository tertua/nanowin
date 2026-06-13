# install_python.ps1 - Python installation module
# Usage: . (Join-Path $SCRIPTS_DIR "install_python.ps1")

# ===== STEP 3: PYTHON =====
Write-Step "===== STEP 3: PREPARE PYTHON ====="
$PythonExe = Join-Path $PY_DIR "python.exe"
if (Test-Path $PythonExe) {
    Write-Info "Python already exists:"
    & $PythonExe --version
} else {
    $PyArch = $ArchPython
    $PyUrl = "https://www.python.org/ftp/python/$PyVer/python-$PyVer-embed-$PyArch.zip"
    $PyZip = Join-Path $TMP_DIR "python-embed.zip"
    Write-Info "Download Python $PyVer ($PyArch)..."
    Download-Helper -Url $PyUrl -Out $PyZip
    if (-not (Test-Path $PyZip)) {
        Write-Error "Failed to download Python!"
        Write-Info "Manual download: $PyUrl"
        Write-Info "Save to: $PyZip"
        pause
        exit 1
    }
    $fi = Get-Item $PyZip
    Write-Info "File size: $($fi.Length) bytes"
    Write-Info "Extracting..."
    Extract-Helper -Zip $PyZip -Dest $PY_DIR
    if (-not (Test-Path $PythonExe)) {
        Write-Error "Failed to extract Python!"
        pause
        exit 1
    }
    Write-Info "Patching ._pth..."
    Get-ChildItem -Path $PY_DIR -Filter "*._pth" | ForEach-Object {
        (Get-Content $_.FullName) -replace '^#import site$', 'import site' | Set-Content $_.FullName
        Add-Content -Path $_.FullName -Value @("Lib", "Lib\site-packages", "..\app")
    }
    Write-Info "Python installed:"
    & $PythonExe --version
}
Write-OK ""

# ===== STEP 4: PIP =====
Write-Step "===== STEP 4: PREPARE PIP ====="
$pipExists = $false
try {
    $null = & $PythonExe -m pip --version 2>&1
    if ($LASTEXITCODE -eq 0) { $pipExists = $true }
} catch {}
if ($pipExists) {
    Write-Info "pip already exists:"
    & $PythonExe -m pip --version
} else {
    $GetPip = Join-Path $TMP_DIR "get-pip.py"
    Write-Info "Download get-pip.py..."
    Download-Helper -Url "https://bootstrap.pypa.io/get-pip.py" -Out $GetPip
    if (-not (Test-Path $GetPip)) {
        Write-Error "Failed to download get-pip.py"
        pause
        exit 1
    }
    Write-Info "Installing pip..."
    & $PythonExe $GetPip --no-warn-script-location
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install pip"
        pause
        exit 1
    }
    Write-Info "pip installed:"
    & $PythonExe -m pip --version
}
Write-OK ""
