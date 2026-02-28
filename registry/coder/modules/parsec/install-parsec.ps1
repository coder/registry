$ProgressPreference = "SilentlyContinue"

$installerUrl = "${INSTALLER_URL}"
$installerPath = Join-Path $env:TEMP "parsec-windows.exe"

Write-Output "Downloading Parsec from $installerUrl"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

Write-Output "Installing Parsec"
Start-Process -FilePath $installerPath -ArgumentList "${INSTALLER_ARGS}" -Wait

Remove-Item $installerPath -Force
