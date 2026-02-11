# Windows RDP Keep Alive Service for Coder
# This script monitors RDP sessions and reports activity to Coder

param(
    [int]$CheckInterval = 60,
    [bool]$Verbose = $false,
    [string]$CoderAgentToken = $env:CODER_AGENT_TOKEN,
    [string]$CoderAgentUrl = $env:CODER_AGENT_URL
)

# Configuration
$ServiceName = "CoderRDPKeepAlive"
$LogSource = "CoderRDPKeepAlive"
$LastSessionState = $false
$ConsecutiveErrors = 0
$MaxConsecutiveErrors = 5

# Ensure running as a service or background process
if (-not $env:CODER_RDP_KEEPALIVE_DAEMON) {
    Write-Host "Starting Coder RDP Keep Alive daemon..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -CheckInterval $CheckInterval -Verbose `$$Verbose" -WindowStyle Hidden
    exit
}

# Logging function
function Write-KeepAliveLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if ($Verbose -or $Level -ne "DEBUG") {
        Write-Host $logMessage
    }
    
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($LogSource)) {
            $eventLevel = switch ($Level) {
                "ERROR" { [System.Diagnostics.EventLogEntryType]::Error }
                "WARN"  { [System.Diagnostics.EventLogEntryType]::Warning }
                default { [System.Diagnostics.EventLogEntryType]::Information }
            }
            Write-EventLog -LogName Application -Source $LogSource -EntryType $eventLevel -EventId 1 -Message $Message
        }
    } catch {
        # Event log write failed, ignore
    }
}

# Function to detect active RDP sessions
function Get-ActiveRDPSessions {
    try {
        $sessions = @()
        
        # Method 1: qwinsta (Query Windows Station)
        try {
            $qwinstaOutput = qwinsta 2>$null
            if ($qwinstaOutput) {
                $activeSessions = $qwinstaOutput | Select-String "Active" | Select-String "rdp-tcp"
                if ($activeSessions) {
                    $sessions += $activeSessions
                }
            }
        } catch {
            Write-KeepAliveLog "qwinsta failed: $($_.Exception.Message)" "DEBUG"
        }
        
        # Method 2: query user
        try {
            $queryOutput = query user 2>$null
            if ($queryOutput) {
                $activeUsers = $queryOutput | Select-String "Active" | Select-String "rdp"
                if ($activeUsers) {
                    $sessions += $activeUsers
                }
            }
        } catch {
            Write-KeepAliveLog "query user failed: $($_.Exception.Message)" "DEBUG"
        }
        
        # Method 3: WMI/CIM
        try {
            $wmiSessions = Get-CimInstance -ClassName Win32_LogonSession -Filter "LogonType=10" -ErrorAction SilentlyContinue
            if ($wmiSessions) {
                $sessions += $wmiSessions
            }
        } catch {
            Write-KeepAliveLog "WMI query failed: $($_.Exception.Message)" "DEBUG"
        }
        
        return ($sessions.Count -gt 0)
    }
    catch {
        Write-KeepAliveLog "Error detecting RDP sessions: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to report activity to Coder
function Report-CoderActivity {
    param([bool]$SessionActive)
    
    if (-not $CoderAgentToken -or -not $CoderAgentUrl) {
        Write-KeepAliveLog "Coder agent configuration missing" "WARN"
        return $false
    }
    
    try {
        $headers = @{
            "Coder-Session-Token" = $CoderAgentToken
            "Content-Type" = "application/json"
        }
        
        $body = @{
            connection_type = "rdp"
            session_active = $SessionActive
            timestamp = (Get-Date -Format "o")
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$CoderAgentUrl/api/v2/workspaceagents/me/report-activity" -Method Post -Headers $headers -Body $body -TimeoutSec 30
        
        Write-KeepAliveLog "Activity reported successfully (RDP Active: $SessionActive)" "DEBUG"
        $ConsecutiveErrors = 0
        return $true
    }
    catch {
        $ConsecutiveErrors++
        Write-KeepAliveLog "Failed to report activity (Error #$ConsecutiveErrors): $($_.Exception.Message)" "WARN"
        return $false
    }
}

# Main loop
Write-KeepAliveLog "Coder RDP Keep Alive service started (CheckInterval: $CheckInterval seconds)"

while ($true) {
    try {
        $hasActiveRDP = Get-ActiveRDPSessions
        
        # Report activity if RDP is active
        if ($hasActiveRDP) {
            if (-not $LastSessionState) {
                Write-KeepAliveLog "RDP session detected - starting activity reporting"
            }
            
            $reported = Report-CoderActivity -SessionActive $true
            
            if ($reported) {
                Write-KeepAliveLog "Activity bump sent for active RDP session"
            }
        }
        else {
            if ($LastSessionState) {
                Write-KeepAliveLog "RDP session ended - stopping activity reporting"
            }
        }
        
        $LastSessionState = $hasActiveRDP
        
        # Reset error counter on success
        if ($ConsecutiveErrors -gt 0 -and $hasActiveRDP) {
            $ConsecutiveErrors = 0
        }
        
        # Exit if too many consecutive errors
        if ($ConsecutiveErrors -ge $MaxConsecutiveErrors) {
            Write-KeepAliveLog "Too many consecutive errors ($MaxConsecutiveErrors), exiting" "ERROR"
            break
        }
    }
    catch {
        Write-KeepAliveLog "Unexpected error in main loop: $($_.Exception.Message)" "ERROR"
    }
    
    # Wait before next check
    Start-Sleep -Seconds $CheckInterval
}

Write-KeepAliveLog "Coder RDP Keep Alive service stopped"
