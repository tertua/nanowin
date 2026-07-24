# setup_helpers.ps1 - Helper functions for setup process

function Write-OK {
    param([string]$T)
    Write-Host "         $T" -ForegroundColor Gray
}

function Write-Step {
    param([string]$T)
    Write-Host "`n$T" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$T)
    Write-Host "         $T" -ForegroundColor Gray
}

function Write-Error {
    param([string]$T)
    Write-Host "  [ERROR] $T" -ForegroundColor Red
}

function Write-Header {
    param([string]$T)
    Write-Host "$T" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$T)
    Write-Host "  [WARN] $T" -ForegroundColor Yellow
}

function Download-Helper {
    param([string]$Url, [string]$Out)
    & (Join-Path $SCRIPTS_DIR "setup\download.ps1") -Url $Url -Out $Out
}

function Extract-Helper {
    param([string]$Zip, [string]$Dest)
    & (Join-Path $SCRIPTS_DIR "setup\extract.ps1") -Zip $Zip -Dest $Dest
}

function Verify-Hash {
    param([string]$Path, [string]$Expected, [string]$Label)
    if (-not (Test-Path $Path)) {
        throw "$Label not found at $Path — cannot verify hash"
    }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        Write-Host "  [ERROR] $Label SHA-256 mismatch!" -ForegroundColor Red
        Write-Host "          Expected: $Expected" -ForegroundColor Red
        Write-Host "          Actual:   $actual" -ForegroundColor Red
        throw "Hash mismatch for $Label"
    }
    Write-Info "SHA-256 OK: $Label"
}

function Flatten-ExtractedDir {
    param([string]$BaseDir, [string]$SearchExe)
    $nested = Get-ChildItem -Path $BaseDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName $SearchExe) } | Select-Object -First 1
    if ($nested) {
        Get-ChildItem -Path $nested.FullName -Recurse | Move-Item -Destination $BaseDir -Force
        Remove-Item -Path $nested.FullName -Recurse -Force
    }
}
