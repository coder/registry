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

variable "display_name" {
  type        = string
  description = "The display name for the Parsec app button."
  default     = "Parsec"
}

variable "slug" {
  type        = string
  description = "The slug for the Parsec app button."
  default     = "parsec"
}

variable "icon" {
  type        = string
  description = "The icon to use for the Parsec app button."
  default     = "/icon/desktop.svg"
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

variable "installer_url" {
  type        = string
  description = "Parsec installer URL."
  default     = "https://builds.parsec.app/package/parsec-windows.exe"
}

variable "installer_args" {
  type        = string
  description = "Installer arguments for silent install."
  default     = "/S"
}

variable "app_url" {
  type        = string
  description = "URL used for the Parsec app button."
  default     = "parsec://"
}

variable "tooltip" {
  type        = string
  description = "Tooltip shown for the Parsec app button."
  default     = "Install the Parsec client locally, then connect to this workspace after signing in on the host."
}

resource "coder_script" "parsec_install" {
  agent_id     = var.agent_id
  display_name = "Install Parsec"
  icon         = var.icon
  run_on_start = true
  script = templatefile("${path.module}/install-parsec.ps1", {
    INSTALLER_URL  = var.installer_url
    INSTALLER_ARGS = var.installer_args
  })
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = var.app_url
  icon         = var.icon
  external     = true
  order        = var.order
  group        = var.group
  tooltip      = var.tooltip
}
