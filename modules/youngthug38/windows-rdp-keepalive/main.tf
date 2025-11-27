script = <<EOT
$Interval = ${var.interval}

Write-Host "Starting RDP Keep Alive Monitor..."

while ($true) {
    # Check for active RDP-Tcp sessions using qwinsta (Standard on Windows Server)
    $sessionInfo = qwinsta | Select-String "rdp-tcp"
    $isActive = $sessionInfo | Select-String "Active"
    
    if ($isActive) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] Active RDP Session Detected."
        
        # Hit the Coder Agent API to verify activity
        # The agent listens on localhost and accepts POST /api/v2/workspace/activity
        try {
            $url = "$env:CODER_AGENT_URL/api/v2/workspace/activity"
            Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body '{}' -ErrorAction SilentlyContinue
            Write-Host " -> Heartbeat sent to Coder Agent."
        } catch {
            Write-Host " -> Failed to send heartbeat: $_"
        }
    }
    
    Start-Sleep -Seconds $Interval
}
EOT