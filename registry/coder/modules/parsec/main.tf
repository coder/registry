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
  description = "The display name for the Parsec application."
  default     = "Parsec"
}

variable "slug" {
  type        = string
  description = "The slug for the Parsec application."
  default     = "parsec"
}

variable "icon" {
  type        = string
  description = "The icon for the Parsec application."
  default     = "/icon/parsec.svg"
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

variable "parsec_team_id" {
  type        = string
  description = "Parsec Team ID for enterprise/team deployments. Leave empty for personal use."
  default     = ""
}

variable "parsec_team_key" {
  type        = string
  description = "Parsec Team Computer Key for headless authentication. Required for automated deployments."
  default     = ""
  sensitive   = true
}

variable "host_name" {
  type        = string
  description = "Custom hostname for the Parsec host. Defaults to workspace name."
  default     = ""
}

variable "auto_start" {
  type        = bool
  description = "Automatically start Parsec service after installation."
  default     = true
}

resource "coder_script" "parsec" {
  agent_id     = var.agent_id
  display_name = "Parsec"
  icon         = var.icon

  script = templatefile("${path.module}/install-parsec.ps1", {
    parsec_team_id  = var.parsec_team_id
    parsec_team_key = var.parsec_team_key
    host_name       = var.host_name
    auto_start      = var.auto_start
  })

  run_on_start = true
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "https://web.parsec.app/"
  icon         = var.icon
  external     = true
  order        = var.order
  group        = var.group
}

resource "coder_app" "parsec-docs" {
  agent_id     = var.agent_id
  display_name = "Parsec Docs"
  slug         = "parsec-docs"
  icon         = "/icon/book.svg"
  url          = "https://support.parsec.app/hc/en-us"
  external     = true
}

data "coder_workspace" "me" {}

output "host_name" {
  description = "The hostname configured for this Parsec host"
  value       = var.host_name != "" ? var.host_name : data.coder_workspace.me.name
}
