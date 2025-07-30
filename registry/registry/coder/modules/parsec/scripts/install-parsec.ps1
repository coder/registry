# Install Parsec on Windows
$parsecUrl = "https://builds.parsecgaming.com/package/parsec-windows.exe"
$installer = "$env:TEMP\parsec-windows.exe"

Invoke-WebRequest -Uri $parsecUrl -OutFile $installer
Start-Process -FilePath $installer -ArgumentList "/S" -Wait

# Start Parsec (assumes default install path)
$parsecPath = "C:\Program Files\Parsec\parsecd.exe"
if (Test-Path $parsecPath) {
    Start-Process -FilePath $parsecPath
} else {
    Write-Error "Parsec executable not found at $parsecPath"
}