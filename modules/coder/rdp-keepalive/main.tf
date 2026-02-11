terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "check_interval" {
  type        = number
  description = "Interval in seconds to check for RDP sessions"
  default     = 60
}

variable "verbose" {
  type        = bool
  description = "Enable verbose logging"
  default     = false
}

# Coder agent resource
data "coder_workspace" "me" {}

# RDP Keep Alive script for Windows
resource "coder_script" "rdp_keepalive" {
  agent_id     = var.agent_id
  display_name = "RDP Keep Alive"
  icon         = "/icon/windows.svg"
  script = templatefile("${path.module}/scripts/rdp-keepalive.ps1", {
    check_interval = var.check_interval
    verbose        = var.verbose
    coder_agent_token = var.coder_agent_token
    coder_agent_url   = var.coder_agent_url
  })
  run_on_start = true
}

variable "agent_id" {
  type        = string
  description = "The ID of the Coder agent"
}

variable "coder_agent_token" {
  type        = string
  description = "Coder agent authentication token"
  sensitive   = true
}

variable "coder_agent_url" {
  type        = string
  description = "Coder agent API URL"
}

output "script_id" {
  value       = coder_script.rdp_keepalive.id
  description = "ID of the created RDP keepalive script"
}
