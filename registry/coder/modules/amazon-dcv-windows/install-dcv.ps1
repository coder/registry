# Terraform variables
$adminPassword = "${admin_password}"
$port = "${port}"
$webURLPath = "${web_url_path}"

function Set-LocalAdminUser {
    Write-Output "[INFO] Starting Set-LocalAdminUser function"
    $securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
    Write-Output "[DEBUG] Secure password created"
    Get-LocalUser -Name Administrator | Set-LocalUser -Password $securePassword
    Write-Output "[INFO] Administrator password set"
    Get-LocalUser -Name Administrator | Enable-LocalUser
    Write-Output "[INFO] User Administrator enabled successfully"
    Read-Host "[DEBUG] Press Enter to proceed to the next step"
}

function Get-VirtualDisplayDriverRequired {
    Write-Output "[INFO] Starting Get-VirtualDisplayDriverRequired function"
    $token = Invoke-RestMethod -Headers @{'X-aws-ec2-metadata-token-ttl-seconds' = '21600'} -Method PUT -Uri http://169.254.169.254/latest/api/token
    Write-Output "[DEBUG] Token acquired: $token"
    $instanceType = Invoke-RestMethod -Headers @{'X-aws-ec2-metadata-token' = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-type
    Write-Output "[DEBUG] Instance type: $instanceType"
    $OSVersion = ((Get-ItemProperty -Path "Microsoft.PowerShell.Core\Registry::\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName) -replace "[^0-9]", ''
    Write-Output "[DEBUG] OS version: $OSVersion"

    # Force boolean result
    $result = (($OSVersion -ne "2019") -and ($OSVersion -ne "2022") -and ($OSVersion -ne "2025")) -and (($instanceType[0] -ne 'g') -and ($instanceType[0] -ne 'p'))
    Write-Output "[INFO] VirtualDisplayDriverRequired result: $result"
    Read-Host "[DEBUG] Press Enter to proceed to the next step"
    return [bool]$result
}

function Download-DCV {
    param (
        [bool]$VirtualDisplayDriverRequired
    )
    Write-Output "[INFO] Starting Download-DCV function"

    $downloads = @(
        @{
            Name = "DCV Display Driver"
            Required = $VirtualDisplayDriverRequired
            Path = "C:\Windows\Temp\DCVDisplayDriver.msi"
            Uri = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-virtual-display-x64-Release.msi"
        },
        @{
            Name = "DCV Server"
            Required = $true
            Path = "C:\Windows\Temp\DCVServer.msi"
            Uri = "https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-server-x64-Release.msi"
        }
    )

    foreach ($download in $downloads) {
        if ($download.Required -and -not (Test-Path $download.Path)) {
            try {
                Write-Output "[INFO] Downloading $($download.Name)"

                # Display progress manually (no events)
                $progressActivity = "Downloading $($download.Name)"
                $progressStatus = "Starting download..."
                Write-Progress -Activity $progressActivity -Status $progressStatus -PercentComplete 0

                # Synchronously download the file
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($download.Uri, $download.Path)

                # Update progress
                Write-Progress -Activity $progressActivity -Status "Completed" -PercentComplete 100

                Write-Output "[INFO] $($download.Name) downloaded successfully."
            } catch {
                Write-Output "[ERROR] Failed to download $($download.Name): $_"
                throw
            }
        } else {
            Write-Output "[INFO] $($download.Name) already exists. Skipping download."
        }
    }

    Write-Output "[INFO] All downloads completed"
    Read-Host "[DEBUG] Press Enter to proceed to the next step"
}

function Install-DCV {
    param (
        [bool]$VirtualDisplayDriverRequired
    )
    Write-Output "[INFO] Starting Install-DCV function"

    if (-not (Get-Service -Name "dcvserver" -ErrorAction SilentlyContinue)) {
        if ($VirtualDisplayDriverRequired) {
            Write-Output "[INFO] Installing DCV Display Driver"
            Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/I C:\Windows\Temp\DCVDisplayDriver.msi /quiet /norestart" -Wait
        } else {
            Write-Output "[INFO] DCV Display Driver installation skipped (not required)."
        }
        Write-Output "[INFO] Installing DCV Server"
        Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/I C:\Windows\Temp\DCVServer.msi ADDLOCAL=ALL /quiet /norestart /l*v C:\Windows\Temp\dcv_install_msi.log" -Wait
    } else {
        Write-Output "[INFO] DCV Server already installed, skipping installation."
    }

    # Wait for the service to appear with a timeout
    $timeout = 10  # seconds
    $elapsed = 0
    while (-not (Get-Service -Name "dcvserver" -ErrorAction SilentlyContinue) -and ($elapsed -lt $timeout)) {
        Start-Sleep -Seconds 1
        $elapsed++
    }

    if ($elapsed -ge $timeout) {
        Write-Output "[WARNING] Timeout waiting for dcvserver service. A restart is required to complete installation."
        Restart-SystemForDCV
    } else {
        Write-Output "[INFO] dcvserver service detected successfully."
    }
}

function Restart-SystemForDCV {
    Write-Output "[INFO] The system will restart in 10 seconds to finalize DCV installation."
    Start-Sleep -Seconds 10

    # Initiate restart
    Restart-Computer -Force

    # Exit the script after initiating restart
    Write-Output "[INFO] Please wait for the system to restart..."

    Exit 1
}


function Configure-DCV {
    Write-Output "[INFO] Starting Configure-DCV function"
    $dcvPath = "Microsoft.PowerShell.Core\Registry::\HKEY_USERS\S-1-5-18\Software\GSettings\com\nicesoftware\dcv"
    
    # Create the required paths
    @("$dcvPath\connectivity", "$dcvPath\session-management", "$dcvPath\session-management\automatic-console-session", "$dcvPath\display") | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -Force | Out-Null
        }
    }
    
    # Set registry keys
    New-ItemProperty -Path "$dcvPath\session-management" -Name create-session -PropertyType DWORD -Value 1 -Force
    New-ItemProperty -Path "$dcvPath\session-management\automatic-console-session" -Name owner -Value Administrator -Force
    New-ItemProperty -Path "$dcvPath\connectivity" -Name quic-port -PropertyType DWORD -Value $port -Force
    New-ItemProperty -Path "$dcvPath\connectivity" -Name web-port -PropertyType DWORD -Value $port -Force
    New-ItemProperty -Path "$dcvPath\connectivity" -Name web-url-path -PropertyType String -Value $webURLPath -Force

    # Attempt to restart service
    if (Get-Service -Name "dcvserver" -ErrorAction SilentlyContinue) {
        Restart-Service -Name "dcvserver"
    } else {
        Write-Output "[WARNING] dcvserver service not found. Ensure the system was restarted properly."
    }

    Write-Output "[INFO] DCV configuration completed"
    Read-Host "[DEBUG] Press Enter to proceed to the next step"
}

# Main Script Execution
Write-Output "[INFO] Starting script"
$VirtualDisplayDriverRequired = [bool](Get-VirtualDisplayDriverRequired)
Set-LocalAdminUser
Download-DCV -VirtualDisplayDriverRequired $VirtualDisplayDriverRequired
Install-DCV -VirtualDisplayDriverRequired $VirtualDisplayDriverRequired
Configure-DCV
Write-Output "[INFO] Script completed"
