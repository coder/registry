# Moonlight Installation Script for Windows
# Installs and configures Moonlight streaming with automatic GPU detection

param(
    [string]$STREAMING_METHOD = "auto",
    [int]$PORT = 47984,
    [string]$QUALITY = "high"
)

Write-Host "Starting Moonlight installation..."

# Function to detect GPU and determine streaming method
function Detect-GPU {
    Write-Host "Detecting GPU hardware..."
    
    $videoControllers = Get-WmiObject -Class Win32_VideoController
    $nvidiaGPUs = $videoControllers | Where-Object {$_.Name -like "*NVIDIA*"}
    
    if ($nvidiaGPUs) {
        Write-Host "NVIDIA GPU detected:"
        foreach ($gpu in $nvidiaGPUs) {
            Write-Host "  - $($gpu.Name)"
        }
        
        $geForcePath = "${env:ProgramFiles}\NVIDIA Corporation\NVIDIA GeForce Experience"
        if (Test-Path $geForcePath) {
            Write-Host "GeForce Experience found - using GameStream"
            return "gamestream"
        } else {
            Write-Host "GeForce Experience not found - using Sunshine"
            return "sunshine"
        }
    } else {
        Write-Host "No NVIDIA GPU detected - using Sunshine"
        return "sunshine"
    }
}

# Determine streaming method
if ($STREAMING_METHOD -eq "auto") {
    $STREAMING_METHOD = Detect-GPU
}

Write-Host "Using streaming method: $STREAMING_METHOD"

# Install Moonlight client
Write-Host "Installing Moonlight client..."
$moonlightUrl = "https://github.com/moonlight-stream/moonlight-qt/releases/latest/download/Moonlight-qt-x64.exe"
$moonlightInstaller = "$env:TEMP\Moonlight-qt-x64.exe"

try {
    Invoke-WebRequest -Uri $moonlightUrl -OutFile $moonlightInstaller -UseBasicParsing
    Write-Host "Moonlight client downloaded successfully"
} catch {
    Write-Error "Failed to download Moonlight client: $($_.Exception.Message)"
    exit 1
}

# Install Moonlight client
try {
    Start-Process -FilePath $moonlightInstaller -ArgumentList "/S" -Wait -NoNewWindow
    Write-Host "Moonlight client installed successfully"
} catch {
    Write-Error "Failed to install Moonlight client: $($_.Exception.Message)"
    exit 1
}

# Configure streaming server based on method
if ($STREAMING_METHOD -eq "gamestream") {
    Write-Host "Configuring NVIDIA GameStream..."
    
    # Check if GeForce Experience is installed
    $geForcePath = "${env:ProgramFiles}\NVIDIA Corporation\NVIDIA GeForce Experience"
    if (Test-Path $geForcePath) {
        Write-Host "GeForce Experience found - GameStream should be enabled"
        Write-Host "Please ensure GameStream is enabled in GeForce Experience settings"
    } else {
        Write-Host "GeForce Experience not found - please install it for GameStream"
    }
} else {
    Write-Host "Installing Sunshine server..."
    
    # Download and install Sunshine
    $sunshineUrl = "https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-windows.zip"
    $sunshineZip = "$env:TEMP\sunshine-windows.zip"
    $sunshineDir = "$env:PROGRAMFILES\Sunshine"
    
    try {
        Invoke-WebRequest -Uri $sunshineUrl -OutFile $sunshineZip -UseBasicParsing
        Expand-Archive -Path $sunshineZip -DestinationPath $sunshineDir -Force
        Write-Host "Sunshine installed successfully"
    } catch {
        Write-Error "Failed to install Sunshine: $($_.Exception.Message)"
        exit 1
    }
    
    # Configure Sunshine
    $sunshineConfig = @"
# Sunshine Configuration
port = $PORT
quality = $QUALITY
fps = 60
encoder = nvenc
"@
    
    $sunshineConfig | Out-File -FilePath "$sunshineDir\sunshine.conf" -Encoding UTF8
    Write-Host "Sunshine configured successfully"
}

# Configure firewall rules
Write-Host "Configuring firewall rules..."
try {
    New-NetFirewallRule -DisplayName "Moonlight Streaming" -Direction Inbound -Protocol TCP -LocalPort $PORT -Action Allow
    Write-Host "Firewall rule added successfully"
} catch {
    Write-Warning "Failed to add firewall rule: $($_.Exception.Message)"
}

Write-Host "Moonlight installation completed successfully"
Write-Host "Streaming method: $STREAMING_METHOD"
Write-Host "Port: $PORT"
Write-Host "Quality: $QUALITY" 