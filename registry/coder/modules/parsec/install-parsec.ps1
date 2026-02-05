# Parsec Installation Script for Coder Workspaces
# This script installs and configures Parsec for cloud gaming and remote desktop

$ErrorActionPreference = "Stop"

Write-Output "=== Installing Parsec for Coder Workspace ==="

# Configuration from Terraform variables
$ParsecTeamId = "${parsec_team_id}"
$ParsecTeamKey = "${parsec_team_key}"
$HostName = "${host_name}"
$AutoStart = [System.Convert]::ToBoolean("${auto_start}")

# Parsec download URL and paths
$ParsecMsiUrl = "https://builds.parsec.app/package/parsec-windows.msi"
$ParsecInstallDir = "$env:ProgramFiles\Parsec"
$TempDir = "$env:TEMP\parsec-install"
$ParsecMsiPath = "$TempDir\parsec-windows.msi"

# Create temp directory
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Check if Parsec is already installed
$ParsecInstalled = Test-Path "$ParsecInstallDir\parsecd.exe"

if (-not $ParsecInstalled) {
    Write-Output "Downloading Parsec..."
    
    # Download Parsec MSI
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -Uri $ParsecMsiUrl -OutFile $ParsecMsiPath -UseBasicParsing
    } catch {
        Write-Error "Failed to download Parsec: $_"
        exit 1
    }
    
    Write-Output "Installing Parsec..."
    
    # Install Parsec silently
    $InstallArgs = @(
        "/i"
        "`"$ParsecMsiPath`""
        "/qn"
        "/norestart"
        "ALLUSERS=1"
    )
    
    $InstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
    
    if ($InstallProcess.ExitCode -ne 0) {
        Write-Error "Parsec installation failed with exit code: $($InstallProcess.ExitCode)"
        exit 1
    }
    
    Write-Output "Parsec installed successfully."
} else {
    Write-Output "Parsec is already installed."
}

# Configure Parsec for headless/team deployment if credentials provided
$ParsecConfigDir = "$env:APPDATA\Parsec"
$ParsecConfigFile = "$ParsecConfigDir\config.txt"

if (-not (Test-Path $ParsecConfigDir)) {
    New-Item -ItemType Directory -Path $ParsecConfigDir -Force | Out-Null
}

# Build configuration
$ConfigLines = @()

# Set hostname if provided
if ($HostName -ne "") {
    $ConfigLines += "host_name = $HostName"
    Write-Output "Setting Parsec host name to: $HostName"
}

# Enable hosting
$ConfigLines += "host_virtual_monitors = 1"
$ConfigLines += "host_privacy_mode = 0"

# Write config if we have any settings
if ($ConfigLines.Count -gt 0) {
    # Read existing config if present
    $ExistingConfig = @()
    if (Test-Path $ParsecConfigFile) {
        $ExistingConfig = Get-Content $ParsecConfigFile
    }
    
    # Merge configs (new values override existing)
    $ConfigHash = @{}
    foreach ($line in $ExistingConfig) {
        if ($line -match "^([^=]+)=(.*)$") {
            $ConfigHash[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    foreach ($line in $ConfigLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            $ConfigHash[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    
    # Write merged config
    $FinalConfig = $ConfigHash.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }
    $FinalConfig | Out-File -FilePath $ParsecConfigFile -Encoding UTF8
    
    Write-Output "Parsec configuration updated."
}

# Configure for Parsec Teams if credentials provided
if ($ParsecTeamId -ne "" -and $ParsecTeamKey -ne "") {
    Write-Output "Configuring Parsec Teams authentication..."
    
    # For Parsec Teams, we need to configure the team computer key
    $TeamConfigFile = "$ParsecConfigDir\team_config.txt"
    @"
team_id = $ParsecTeamId
team_computer_key = $ParsecTeamKey
"@ | Out-File -FilePath $TeamConfigFile -Encoding UTF8
    
    Write-Output "Parsec Teams configuration saved."
}

# Start Parsec if auto_start is enabled
if ($AutoStart) {
    Write-Output "Starting Parsec..."
    
    $ParsecExe = "$ParsecInstallDir\parsecd.exe"
    
    if (Test-Path $ParsecExe) {
        # Start Parsec in the background
        Start-Process -FilePath $ParsecExe -WindowStyle Hidden
        Write-Output "Parsec started successfully."
    } else {
        Write-Warning "Parsec executable not found at: $ParsecExe"
    }
}

# Cleanup
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "=== Parsec installation complete ==="
Write-Output ""
Write-Output "To connect to this workspace:"
Write-Output "1. Install Parsec client on your local machine: https://parsec.app/downloads"
Write-Output "2. Log in to your Parsec account"
Write-Output "3. This computer will appear in your Parsec computer list"
Write-Output ""
Write-Output "For Teams deployment, ensure you have configured team_id and team_computer_key."
