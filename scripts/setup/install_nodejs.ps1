# install_nodejs.ps1 - Node.js installation module
# Usage: . (Join-Path $SCRIPTS_DIR "install_nodejs.ps1")

# ===== STEP 4.7: NODE.JS =====
Write-Step "===== STEP 4.7: CHECK NODE.JS ====="
$NodeDir = Join-Path $ROOT "bin\nodejs"
$NodeExe = Join-Path $NodeDir "node.exe"
$NodeReady = $false
if (Test-Path $NodeExe) {
    Write-Info "Node.js portable found on USB."
    $env:PATH = "$ROOT\bin\nodejs;$env:PATH"
    $NodeReady = $true
} else {
    Write-Info "Node.js not found, downloading portable..."
    Write-Info "Download Node.js v$NodeVer ($ArchNode)..."
    $NodeZipUrl = "https://nodejs.org/dist/v$NodeVer/node-v$NodeVer-win-$ArchNode.zip"
    $NodeZip = Join-Path $TMP_DIR "node-v$NodeVer-win-$ArchNode.zip"
    Download-Helper -Url $NodeZipUrl -Out $NodeZip
    if (-not (Test-Path $NodeZip)) {
        throw "Failed to download Node.js!"
    }
    $nodeHashes = @{ "x64" = "57693d8e93d1b04e7b7de46aca53ecd63e97564e73de36a68428d7ff08d83587" }
    if ($nodeHashes.ContainsKey($ArchNode)) {
        Verify-Hash -Path $NodeZip -Expected $nodeHashes[$ArchNode] -Label "Node.js v$NodeVer $ArchNode"
    }
    Write-Info "Extracting..."
    if (Test-Path $NodeDir) { Remove-Item -Path $NodeDir -Recurse -Force }
    Extract-Helper -Zip $NodeZip -Dest $NodeDir
    if (Test-Path $NodeExe) {
        Write-Info "Node.js installed successfully."
        $env:PATH = "$ROOT\bin\nodejs;$env:PATH"
        $NodeReady = $true
    }
    if (-not $NodeReady) {
        Flatten-ExtractedDir -BaseDir $NodeDir -SearchExe "node.exe"
        if (Test-Path $NodeExe) {
            Write-Info "Node.js OK (subfolder)."
            $env:PATH = "$ROOT\bin\nodejs;$env:PATH"
            $NodeReady = $true
        }
    }
    if (-not $NodeReady) {
        if (Test-Path $NodeDir) { Remove-Item -Path $NodeDir -Recurse -Force }
        throw "Node.js extraction failed!"
    }
}
if ($NodeReady) {
    Write-Info "Node.js:"
    & $NodeExe --version
}
Write-OK ""
