# install_gh.ps1 - GitHub CLI (gh) installation module
# Usage: . (Join-Path $SCRIPTS_DIR "install_gh.ps1")

# ===== STEP 4.6: GITHUB CLI =====
Write-Step "===== STEP 4.6: CHECK GITHUB CLI ====="
$GhReady = $false
$GhExe   = Join-Path $ROOT "bin\gh\bin\gh.exe"

if (Test-Path $GhExe) {
    Write-Info "Portable gh found on USB."
    $GhReady = $true
} else {
    Write-Info "gh not found, downloading portable..."
    Write-Info "Download gh v$GhVer ($ArchGh)..."
    $GhUrl = "https://github.com/cli/cli/releases/download/v$GhVer/gh_${GhVer}_windows_${ArchGh}.zip"
    $GhZip = Join-Path $TMP_DIR "gh_${GhVer}_windows_${ArchGh}.zip"
    Download-Helper -Url $GhUrl -Out $GhZip
    if (-not (Test-Path $GhZip)) {
        Write-Error "Failed to download gh!"
        pause
        exit 1
    }
    Write-Info "Extracting..."
    $GhDir = Join-Path $ROOT "bin\gh"
    if (Test-Path $GhDir) { Remove-Item -Path $GhDir -Recurse -Force }
    Extract-Helper -Zip $GhZip -Dest $GhDir
    Flatten-ExtractedDir -BaseDir $GhDir -SearchExe "bin\gh.exe"
    if (Test-Path $GhExe) {
        Write-Info "gh installed successfully."
        $GhReady = $true
    } else {
        Write-Error "gh extraction failed!"
        if (Test-Path $GhDir) { Remove-Item -Path $GhDir -Recurse -Force }
        pause
        exit 1
    }
}
if ($GhReady) {
    $env:PATH = "$ROOT\bin\gh\bin;$env:PATH"
    Write-Info "gh:"
    & gh --version
}
Write-OK ""
