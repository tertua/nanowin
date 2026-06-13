# install_source.ps1 - Nanobot source code download module
# Usage: . (Join-Path $SCRIPTS_DIR "install_source.ps1")

# ===== STEP 5: SOURCE CODE =====
Write-Step "===== STEP 5: PREPARE NANOBOT SOURCE CODE ====="
$SrcOk = $false
if (Test-Path $APP_DIR) {
    if (Test-Path (Join-Path $APP_DIR ".git")) {
        Write-Info "Update repo..."
        & git -C $APP_DIR pull
        $SrcOk = $true
    }
}
if (-not $SrcOk) {
    try {
        $null = & git --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Cloning repository..."
            if (Test-Path $APP_DIR) { Remove-Item -Path $APP_DIR -Recurse -Force }
            & git clone --depth 1 --single-branch --branch main https://github.com/HKUDS/nanobot.git $APP_DIR
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Clone successful."
                $SrcOk = $true
            } else {
                Write-Info "Clone failed, trying ZIP..."
            }
        }
    } catch {}
}
if (-not $SrcOk) {
    $RepoZip = Join-Path $TMP_DIR "nanobot-main.zip"
    Write-Info "Download ZIP..."
    Download-Helper -Url "https://github.com/HKUDS/nanobot/archive/refs/heads/main.zip" -Out $RepoZip
    if (-not (Test-Path $RepoZip)) {
        Write-Error "Failed to download source code!"
        pause
        exit 1
    }
    Write-Info "Extracting ZIP..."
    $ExtractDir = Join-Path $TMP_DIR "repo_extract"
    if (Test-Path $ExtractDir) { Remove-Item -Path $ExtractDir -Recurse -Force }
    New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
    Extract-Helper -Zip $RepoZip -Dest $ExtractDir
    $extracted = Get-ChildItem -Path $ExtractDir -Directory | Select-Object -First 1
    if ($extracted) {
        if (Test-Path $APP_DIR) { Remove-Item -Path $APP_DIR -Recurse -Force }
        Move-Item -Path $extracted.FullName -Destination $APP_DIR -Force
    }
    Remove-Item -Path $ExtractDir -Recurse -Force
    if (Test-Path (Join-Path $APP_DIR "README.md")) {
        Write-OK "ZIP successful."
    } else {
        Write-Error "Extraction failed"
        pause
        exit 1
    }
}
Write-OK ""

# ===== PORTABLE PATHS PATCH =====
$patchScript = Join-Path $SCRIPTS_DIR "portable_paths.py"
if (Test-Path $patchScript) {
    Write-Info "Apply portable paths patch..."
    & $PythonExe $patchScript
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Patch failed. Setup continues."
    } else {
        Write-OK "Path patch applied."
    }
}
Write-OK ""
