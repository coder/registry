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

variable "folder" {
  type        = string
  description = "The folder to open in Positron."
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

variable "slug" {
  type        = string
  description = "The slug of the app."
  default     = "positron"
}

variable "display_name" {
  type        = string
  description = "The display name of the app."
  default     = "Positron Desktop"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.1"

  agent_id = var.agent_id

  web_app_icon         = "https://github.com/posit-dev/positron/raw/4b8cc97a7a7a9468c02cd5ac0ee685192030825d/src/vs/workbench/browser/media/positron-icon.svg"
  web_app_slug         = var.slug
  web_app_display_name = var.display_name
  web_app_order        = var.order
  web_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "positron"
}

output "positron_url" {
  value       = module.vscode-desktop-core.ide_uri
  description = "Positron Desktop URL."
}
