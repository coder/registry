terraform {
  required_version = ">= 1.0"
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "folder" {
  type        = string
  description = "The folder to open in Kiro IDE."
  default     = ""
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
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

module "kiro" {
  # TODO: update this
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/vscode-desktop-core?ref=phorcys420/centralize-vscode-desktop"

  agent_id = var.agent_id

  web_app_icon         = "/icon/kiro.svg"
  web_app_slug         = "kiro"
  web_app_display_name = "Kiro IDE"
  web_app_order        = var.order
  web_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "kiro"
}

output "kiro_url" {
  value       = module.kiro.ide_uri
  description = "Kiro IDE URL."
}