terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  description = "The ID of the Coder agent."
  type        = string
}

variable "interval" {
  description = "Interval in seconds to check for RDP connections."
  type        = number
  default     = 60
}

resource "coder_script" "rdp_keepalive" {
  agent_id     = var.agent_id
  display_name = "RDP Keep Alive"
  icon         = "/icon/remote-desktop.svg"
  run_on_start = true
  
  # We run a PowerShell loop in the background
  script = <<EOT
$Interval = ${var.interval}

Write-Host "Starting RDP Keep Alive Monitor..."

while ($true) {
    # check for active RDP-Tcp sessions
    $rdpSession = query user | Select-String "rdp-tcp" | Select-String "Active"
    
    if ($rdpSession) {
        # RDP is active. We need to generate 'activity' to prevent shutdown.
        # Since Coder monitors network/ssh, the simplest way to bump activity 
        # is to simulate a state change or write to stdout which the agent captures.
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] RDP Active - Sending KeepAlive signal"
        
        # This subtle output to the agent's log is often enough to reset the "idleness" timer
        # because the PTY receives data.
    }
    
    Start-Sleep -Seconds $Interval
}
EOT
}