terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "agent_name" {
  type        = string
  description = "The name of the Coder agent."
  default     = "main"
}

variable "username" {
  type        = string
  description = "The username for RDP authentication."
  default     = "Administrator"
}

variable "password" {
  type        = string
  description = "The password for RDP authentication."
  default     = "coderRDP!"
  sensitive   = true
}

variable "display_name" {
  type        = string
  description = "The display name for the RDP app button."
  default     = "RDP Desktop"
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

locals {
  # Extract server name from workspace access URL
  server_name = regex("https?:\\/\\/([^\\/]+)", data.coder_workspace.me.access_url)[0]
}

data "coder_workspace" "me" {}

resource "coder_app" "rdp_desktop" {
  agent_id     = var.agent_id
  slug         = "rdp-desktop"
  display_name = var.display_name
  url          = "coder://${local.server_name}/v0/open/ws/${data.coder_workspace.me.name}/agent/${var.agent_name}/rdp?username=${var.username}&password=${var.password}"
  icon         = "/icon/desktop.svg"
  external     = true
  order        = var.order
}

output "app" {
  description = "The created RDP desktop app resource"
  value       = coder_app.rdp_desktop
  sensitive   = true
}

