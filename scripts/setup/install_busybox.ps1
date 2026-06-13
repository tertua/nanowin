# install_busybox.ps1 - BusyBox portable installation module
# Usage: . (Join-Path $SCRIPTS_DIR "setup\install_busybox.ps1")

# ===== STEP 3: BUSYBOX =====
Write-Step "===== STEP 3: PREPARE BUSYBOX ====="
$BBExe = Join-Path $PY_DIR "busybox.exe"
if (Test-Path $BBExe) {
    Write-Info "BusyBox already exists."
} else {
    $BBArch = if ($ProcArch -eq "ARM64") { "busybox64a.exe" } else { "busybox64.exe" }
    $BBUrl = "https://frippery.org/files/busybox/$BBArch"
    Write-Info "Download BusyBox ($BBArch)..."
    Download-Helper -Url $BBUrl -Out $BBExe
    if (-not (Test-Path $BBExe)) {
        Write-Error "Failed to download BusyBox!"
        Write-Info "Manual download: $BBUrl"
        Write-Info "Save to: $BBExe"
        pause
        exit 1
    }
    $fi = Get-Item $BBExe
    Write-Info "File size: $($fi.Length) bytes"
    Write-Info "BusyBox installed."
}
$BBSh = Join-Path $PY_DIR "sh.exe"
if (-not (Test-Path $BBSh)) {
    Copy-Item -Path $BBExe -Destination $BBSh -Force
    Write-Info "sh.exe created (copy of busybox.exe)"
}
Write-Info "BusyBox:"
& $BBExe --help 2>&1 | Select-Object -First 3
Write-OK ""
