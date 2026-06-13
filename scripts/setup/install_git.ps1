# install_git.ps1 - MinGit installation module
# Usage: . (Join-Path $SCRIPTS_DIR "install_git.ps1")

# ===== STEP 4.5: GIT =====
Write-Step "===== STEP 4.5: CHECK GIT ====="
$GitReady = $false

# Always use portable MinGit -- ignore host system Git
if (Test-Path (Join-Path $ROOT "bin\git\cmd\git.exe")) {
    Write-Info "Portable git found on USB."
    $GitReady = $true
    $env:PATH = "$ROOT\bin\nodejs;$ROOT\bin\git\cmd;$ROOT\bin\git\$MinGwDir;$env:PATH"
} else {
    Write-Info "Git not found, downloading portable MinGit..."
    Write-Info "Download MinGit..."
    $GitUrl = "https://github.com/git-for-windows/git/releases/download/v${GitVer}.windows.1/MinGit-${GitVer}-${ArchMinGit}.zip"
    $GitZip = Join-Path $TMP_DIR "MinGit-${GitVer}-${ArchMinGit}.zip"
    Download-Helper -Url $GitUrl -Out $GitZip
    if (-not (Test-Path $GitZip)) {
        Write-Error "Failed to download MinGit!"
        pause
        exit 1
    }
    Write-Info "Extracting..."
    $GitDir = Join-Path $ROOT "bin\git"
    if (Test-Path $GitDir) { Remove-Item -Path $GitDir -Recurse -Force }
    Extract-Helper -Zip $GitZip -Dest $GitDir
    if (Test-Path (Join-Path $GitDir "cmd\git.exe")) {
        Write-Info "MinGit installed successfully."
        $GitReady = $true
    }
    if (-not $GitReady) {
        Flatten-ExtractedDir -BaseDir $GitDir -SearchExe "cmd\git.exe"
        if (Test-Path (Join-Path $GitDir "cmd\git.exe")) {
            Write-Info "MinGit OK (subfolder)."
            $GitReady = $true
        }
    }
    if (-not $GitReady) {
        Write-Error "MinGit extraction failed!"
        if (Test-Path $GitDir) { Remove-Item -Path $GitDir -Recurse -Force }
        pause
        exit 1
    }
    $env:PATH = "$ROOT\bin\nodejs;$ROOT\bin\git\cmd;$ROOT\bin\git\$MinGwDir;$env:PATH"
}
Write-Info "Git:"
& git --version
Write-OK ""
