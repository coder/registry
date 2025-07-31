# Install Parsec on Windows
# This script installs Parsec for remote desktop and cloud gaming

$parsecUrl = "https://builds.parsecgaming.com/package/parsec-windows.exe"
$installer = "$env:TEMP\parsec-windows.exe"

Write-Host "Downloading Parsec installer..."
try {
    Invoke-WebRequest -Uri $parsecUrl -OutFile $installer -UseBasicParsing
    Write-Host "Download completed successfully"
} catch {
    Write-Error "Failed to download Parsec installer: $($_.Exception.Message)"
    exit 1
}

Write-Host "Installing Parsec..."
try {
    Start-Process -FilePath $installer -ArgumentList "/S" -Wait -NoNewWindow
    Write-Host "Installation completed successfully"
} catch {
    Write-Error "Failed to install Parsec: $($_.Exception.Message)"
    exit 1
}

# Start Parsec (assumes default install path)
$parsecPath = "C:\Program Files\Parsec\parsecd.exe"
if (Test-Path $parsecPath) {
    Write-Host "Starting Parsec..."
    Start-Process -FilePath $parsecPath -NoNewWindow
    Write-Host "Parsec started successfully"
} else {
    Write-Error "Parsec executable not found at $parsecPath"
    exit 1
}

Write-Host "Parsec installation and startup completed successfully" 