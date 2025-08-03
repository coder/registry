# Install and configure Parsec
$ErrorActionPreference = "Stop"

Write-Host "Starting Parsec installation..."

# Parse configuration from environment variables
$parsecConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($env:PARSEC_CONFIG)) | ConvertFrom-Json

# Download Parsec installer
$tempDir = $env:TEMP
$installerPath = Join-Path $tempDir "parsec-windows.exe"

Write-Host "Downloading Parsec installer..."
if ($env:PARSEC_VERSION -eq "latest") {
    $downloadUrl = "https://builds.parsec.app/package/parsec-windows.exe"
} else {
    $downloadUrl = "https://builds.parsec.app/package/parsec-windows-$env:PARSEC_VERSION.exe"
}

Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# Install Parsec silently
Write-Host "Installing Parsec..."
Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait

# Create Parsec config directory
$parsecConfigDir = "$env:APPDATA\Parsec"
New-Item -ItemType Directory -Force -Path $parsecConfigDir | Out-Null

# Configure Parsec
Write-Host "Configuring Parsec..."
$configContent = @"
# Parsec Configuration
app_host = 1
app_run_level = 3
encoder_bitrate = $($parsecConfig.encoder_bitrate ?? 50)
encoder_fps = $($parsecConfig.encoder_fps ?? 60)
encoder_min_bitrate = 10
bandwidth_limit = $($parsecConfig.bandwidth_limit ?? 100)
encoder_h265 = $($parsecConfig.encoder_h265 ?? "true")
client_keyboard_layout = $($parsecConfig.client_keyboard_layout ?? "en-us")
host_virtual_monitors = 1
"@

if ($env:PARSEC_HOST_KEY) {
    $configContent += "`nhost_key = $env:PARSEC_HOST_KEY"
}

# Configure GPU acceleration if enabled
if ($env:ENABLE_GPU -eq "true") {
    Write-Host "Configuring GPU acceleration..."
    try {
        # Check for NVIDIA GPU
        $gpuInfo = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" }
        if ($gpuInfo) {
            $configContent += "`nencoder_device = 0"
        } else {
            Write-Host "Warning: GPU acceleration enabled but no NVIDIA GPU found"
        }
    } catch {
        Write-Host "Warning: Error checking GPU info: $_"
    }
}

$configContent | Out-File -FilePath "$parsecConfigDir\config.txt" -Encoding ASCII

# Start Parsec if auto-start is enabled
if ($env:AUTO_START -eq "true") {
    Write-Host "Starting Parsec..."
    Start-Process "${env:ProgramFiles}\Parsec\parsecd.exe"
}

Write-Host "Parsec setup complete!"
