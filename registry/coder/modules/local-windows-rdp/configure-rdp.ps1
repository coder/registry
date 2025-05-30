# PowerShell script to configure RDP for Coder Desktop access
# This script enables RDP, sets the admin password, and configures necessary settings

Write-Output "[Coder RDP Setup] Starting RDP configuration..."

# Function to set the administrator password
function Set-AdminPassword {
    param (
        [string]$adminUsername,
        [string]$adminPassword
    )
    
    Write-Output "[Coder RDP Setup] Setting password for user: $adminUsername"
    
    try {
        # Convert password to secure string
        $securePassword = ConvertTo-SecureString -AsPlainText $adminPassword -Force
        
        # Set the password for the user
        Get-LocalUser -Name $adminUsername | Set-LocalUser -Password $securePassword
        
        # Enable the user account (in case it's disabled)
        Get-LocalUser -Name $adminUsername | Enable-LocalUser
        
        Write-Output "[Coder RDP Setup] Successfully set password for $adminUsername"
    } catch {
        Write-Error "[Coder RDP Setup] Failed to set password: $_"
        exit 1
    }
}

# Function to enable and configure RDP
function Enable-RDP {
    Write-Output "[Coder RDP Setup] Enabling Remote Desktop..."
    
    try {
        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
        
        # Disable Network Level Authentication (NLA) for easier access
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force
        
        # Set security layer to RDP Security Layer
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value 1 -Force
        
        Write-Output "[Coder RDP Setup] RDP enabled successfully"
    } catch {
        Write-Error "[Coder RDP Setup] Failed to enable RDP: $_"
        exit 1
    }
}

# Function to configure Windows Firewall for RDP
function Configure-Firewall {
    Write-Output "[Coder RDP Setup] Configuring Windows Firewall for RDP..."
    
    try {
        # Enable RDP firewall rules
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        
        # If the above fails, try alternative method
        if ($LASTEXITCODE -ne 0) {
            netsh advfirewall firewall set rule group="remote desktop" new enable=Yes
        }
        
        Write-Output "[Coder RDP Setup] Firewall configured successfully"
    } catch {
        Write-Warning "[Coder RDP Setup] Failed to configure firewall rules: $_"
        # Continue anyway as RDP might still work
    }
}

# Function to ensure RDP service is running
function Start-RDPService {
    Write-Output "[Coder RDP Setup] Starting Remote Desktop Services..."
    
    try {
        # Start the Terminal Services
        Set-Service -Name "TermService" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "TermService" -ErrorAction SilentlyContinue
        
        # Start Remote Desktop Services UserMode Port Redirector
        Set-Service -Name "UmRdpService" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
        
        Write-Output "[Coder RDP Setup] RDP services started successfully"
    } catch {
        Write-Warning "[Coder RDP Setup] Some RDP services may not have started: $_"
        # Continue anyway
    }
}

# Main execution
try {
    # Template variables from Terraform
    $username = "${username}"
    $password = "${password}"
    
    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        Write-Error "[Coder RDP Setup] Username or password is empty"
        exit 1
    }
    
    # Execute configuration steps
    Set-AdminPassword -adminUsername $username -adminPassword $password
    Enable-RDP
    Configure-Firewall
    Start-RDPService
    
    Write-Output "[Coder RDP Setup] RDP configuration completed successfully!"
    Write-Output "[Coder RDP Setup] You can now connect using:"
    Write-Output "  Username: $username"
    Write-Output "  Password: [hidden]"
    Write-Output "  Port: 3389 (default)"
    
} catch {
    Write-Error "[Coder RDP Setup] An unexpected error occurred: $_"
    exit 1
} 