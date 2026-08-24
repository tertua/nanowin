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
        throw "Failed to download Python!`nManual download: $PyUrl`nSave to: $PyZip"
    }
    $pyHashes = @{ "amd64" = "38b265fc0612027a126ae54d2485101f041b61893e41ef4f421dee6ac618a99e" }
    if ($pyHashes.ContainsKey($PyArch)) {
        Verify-Hash -Path $PyZip -Expected $pyHashes[$PyArch] -Label "Python $PyVer embed $PyArch"
    }
    $fi = Get-Item $PyZip
    Write-Info "File size: $($fi.Length) bytes"
    Write-Info "Extracting..."
    Extract-Helper -Zip $PyZip -Dest $PY_DIR
    if (-not (Test-Path $PythonExe)) {
        throw "Failed to extract Python!"
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
        throw "Failed to download get-pip.py"
    }
    # get-pip.py di bootstrap.pypa.io berubah setiap rilis pip baru (tidak ada
    # URL versi yang stabil). Jika hash mismatch: download ulang file tersebut,
    # hitung `Get-FileHash get-pip.py -Algorithm SHA256`, lalu perbarui di sini.
    # Terakhir dicek: 2026-08-24 (pip 26.2.1)
    Verify-Hash -Path $GetPip -Expected "fb24e693bab954209a063d90953621412ccad4a500905a726286e038f508ddf6" -Label "get-pip.py"
    Write-Info "Installing pip..."
    & $PythonExe $GetPip --no-warn-script-location
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install pip"
    }
    Write-Info "pip installed:"
    & $PythonExe -m pip --version
}
Write-OK ""
