# ============================================
#  Nanobot Portable - ZIP Extract Helper by Simata.id
#  Dipanggil oleh setup.bat
#  Usage: powershell -ExecutionPolicy Bypass -File extract.ps1 -Zip "PATH" -Dest "PATH"
# ============================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Zip,

    [Parameter(Mandatory=$true)]
    [string]$Dest
)

 $ErrorActionPreference = "Stop"

function Write-Status($msg) {
    Write-Host "  PS: $msg"
}

Write-Status "Extracting: $Zip"
Write-Status "Destination: $Dest"

# Pastikan folder tujuan ada
if (!(Test-Path $Dest)) {
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
}

# Metode 1: Expand-Archive
try {
    Write-Status "Metode 1: Expand-Archive..."
    Expand-Archive -Path $Zip -DestinationPath $Dest -Force
    Write-Status "Extract success (Expand-Archive)"
    Write-Status "EXTRACT_SUCCESS"
    exit 0
} catch {
    Write-Status "Metode 1 failed: $($_.Exception.Message)"
}

# Metode 2: Shell.Application COM
try {
    Write-Status "Metode 2: Shell.Application COM..."
    $shell = New-Object -ComObject Shell.Application
    $zipItem = $shell.NameSpace($Zip)
    $destItem = $shell.NameSpace($Dest)
    if ($zipItem -and $destItem) {
        $destItem.CopyHere($zipItem.Items(), 0x610)
        Write-Status "Extract success (Shell.Application)"
        Write-Status "EXTRACT_SUCCESS"
        exit 0
    }
} catch {
    Write-Status "Metode 2 failed: $($_.Exception.Message)"
}

# Metode 3: .NET ZipFile
try {
    Write-Status "Metode 3: .NET System.IO.Compression..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest, $true)
    Write-Status "Extract success (.NET ZipFile)"
    Write-Status "EXTRACT_SUCCESS"
    exit 0
} catch {
    Write-Status "Metode 3 failed: $($_.Exception.Message)"
}

# Metode 4: VBS fallback
try {
    Write-Status "Metode 4: VBS fallback (unzip.vbs)..."
    $VbsScript = Join-Path $PSScriptRoot "unzip.vbs"
    if (Test-Path $VbsScript) {
        $result = & cscript //NoLogo $VbsScript $Zip $Dest 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Extract success (VBS fallback)"
            Write-Status "EXTRACT_SUCCESS"
            exit 0
        } else {
            Write-Status "Metode 4 failed: exit code $LASTEXITCODE"
        }
    } else {
        Write-Status "Metode 4 failed: unzip.vbs not found at $VbsScript"
    }
} catch {
    Write-Status "Metode 4 failed: $($_.Exception.Message)"
}

Write-Status "All metode extract failed!"
Write-Status "EXTRACT_FAILED"
exit 1