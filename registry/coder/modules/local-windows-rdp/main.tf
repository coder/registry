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

variable "agent_name" {
  type        = string
  description = "The name of the Coder agent."
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

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

locals {
  # Extract server name from workspace access URL
  server_name = regex("https?:\\/\\/([^\\/]+)", data.coder_workspace.me.access_url)[0]
}

data "coder_workspace" "me" {}

resource "coder_script" "rdp_setup" {
  agent_id     = var.agent_id
  display_name = "Configure RDP"
  icon         = "/icon/rdp.svg"
  script = templatefile("${path.module}/configure-rdp.ps1", {
    username = var.username
    password = var.password
  })
  run_on_start = true
}

resource "coder_app" "rdp_desktop" {
  agent_id     = var.agent_id
  slug         = "rdp-desktop"
  display_name = var.display_name
  url          = "coder://${local.server_name}/v0/open/ws/${data.coder_workspace.me.name}/agent/${var.agent_name}/rdp?username=${var.username}&password=${var.password}"
  icon         = "/icon/rdp.svg"
  external     = true
  order        = var.order
  group        = var.group
}
