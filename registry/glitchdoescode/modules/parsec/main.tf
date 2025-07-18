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

variable "installation_method" {
  type        = string
  description = "Installation method for Parsec: 'auto' (detect), 'deb' (Ubuntu/Debian), or 'appimage' (universal)"
  default     = "auto"
  validation {
    condition     = contains(["auto", "deb", "appimage"], var.installation_method)
    error_message = "Installation method must be one of: auto, deb, appimage"
  }
}

variable "enable_hardware_acceleration" {
  type        = bool
  description = "Enable hardware acceleration for optimal performance"
  default     = true
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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_script" "parsec" {
  agent_id     = var.agent_id
  display_name = "Parsec"
  icon         = "/icon/desktop.svg"
  script = templatefile("${path.module}/run.sh", {
    INSTALLATION_METHOD         = var.installation_method,
    ENABLE_HARDWARE_ACCELERATION = var.enable_hardware_acceleration ? "true" : "false"
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = "parsec"
  display_name = "Parsec"
  icon         = "/icon/desktop.svg"
  external     = true
  order        = var.order
  group        = var.group
  
  # Parsec uses a custom protocol, so we'll launch the installed app
  url = "parsec://"
}

output "parsec_info" {
  value = {
    installation_method = var.installation_method
    hardware_acceleration = var.enable_hardware_acceleration
    status = "Parsec installation completed"
  }
  description = "Information about the Parsec installation"
}
