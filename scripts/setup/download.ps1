# ============================================
#  Nanobot Portable - Download Helper by Simata.id
#  Dipanggil oleh setup.bat
#  Usage: powershell -ExecutionPolicy Bypass -File download.ps1 -Url "URL" -Out "PATH"
# ============================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Url,

    [Parameter(Mandatory=$true)]
    [string]$Out,

    [int]$TimeoutSec = 300
)

 $ErrorActionPreference = "Stop"

function Write-Status($msg) {
    Write-Host "  PS: $msg"
}

function Download-File($url, $out) {
    Write-Status "Downloading: $url"
    Write-Status "Saving to: $out"

    # Pastikan folder tujuan ada
    $outDir = Split-Path -Parent $out
    if ($outDir -and !(Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Metode 1: Invoke-WebRequest
    try {
        Write-Status "Metode 1: Invoke-WebRequest..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec $TimeoutSec
        if (Test-Path $out) {
            $size = (Get-Item $out).Length
            Write-Status "OK - File size: $size bytes"
            return $true
        }
    } catch {
        Write-Status "Metode 1 failed: $($_.Exception.Message)"
    }

    # Metode 2: WebClient
    try {
        Write-Status "Metode 2: System.Net.WebClient..."
        if (Test-Path $out) { Remove-Item $out -Force }
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $out)
        if (Test-Path $out) {
            $size = (Get-Item $out).Length
            Write-Status "OK - File size: $size bytes"
            return $true
        }
    } catch {
        Write-Status "Metode 2 failed: $($_.Exception.Message)"
    }

    # Metode 3: HttpClient
    try {
        Write-Status "Metode 3: System.Net.Http.HttpClient..."
        if (Test-Path $out) { Remove-Item $out -Force }
        Add-Type -AssemblyName System.Net.Http
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        try {
            $response = $client.GetAsync($url).Result
            $response.EnsureSuccessStatusCode()
            $stream = $response.Content.ReadAsStreamAsync().Result
            $fileStream = [System.IO.File]::Create($out)
            try {
                $stream.CopyTo($fileStream)
            } finally {
                if ($fileStream) { $fileStream.Close() }
                if ($stream) { $stream.Close() }
            }
            if (Test-Path $out) {
                $size = (Get-Item $out).Length
                Write-Status "OK - File size: $size bytes"
                return $true
            }
        } finally {
            if ($response) { $response.Dispose() }
            if ($client) { $client.Dispose() }
            if ($handler) { $handler.Dispose() }
        }
    } catch {
        Write-Status "Metode 3 failed: $($_.Exception.Message)"
    }

    Write-Status "All metode failed!"
    return $false
}

# ===== MAIN =====
Write-Status "Starting download..."
 $result = Download-File -url $Url -out $Out

if ($result) {
    Write-Status "DOWNLOAD_SUCCESS"
    exit 0
} else {
    Write-Status "DOWNLOAD_FAILED"
    exit 1
}