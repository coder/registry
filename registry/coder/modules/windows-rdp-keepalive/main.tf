terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "check_interval" {
  type        = number
  description = "Interval in seconds between RDP connection checks."
  default     = 30
}

variable "enabled" {
  type        = bool
  description = "Whether to enable RDP keep-alive monitoring."
  default     = true
}

resource "coder_script" "rdp-keepalive" {
  count        = var.enabled ? 1 : 0
  agent_id     = var.agent_id
  display_name = "RDP Keep-Alive Monitor"
  icon         = "/icon/rdp.svg"
  run_on_start = true

  script = templatefile("${path.module}/rdp-keepalive.ps1.tftpl", {
    check_interval = var.check_interval
  })
}

output "enabled" {
  description = "Whether RDP keep-alive monitoring is enabled."
  value       = var.enabled
}
