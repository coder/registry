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
  description = "The folder to open in Windsurf Editor."
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
  default     = "windsurf"
}

variable "display_name" {
  type        = string
  description = "The display name of the app."
  default     = "Windsurf Editor"
}

variable "mcp" {
  type        = string
  description = "JSON-encoded string to configure MCP servers for Windsurf. When set, writes ~/.codeium/windsurf/mcp_config.json."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

module "vscode-desktop-core" {
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/vscode-desktop-core?ref=phorcys/vscode-desktop-core-mcp"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/windsurf.svg"
  coder_app_slug         = "windsurf"
  coder_app_display_name = "Windsurf Editor"
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  mcp_config  = var.mcp != null ? jsondecode(var.mcp) : null # turn MCP JSON string into map(any) for vscode-desktop-core module

  protocol      = "windsurf"
  config_folder = "$HOME/.codeium/windsurf"
}

output "windsurf_url" {
  value       = module.vscode-desktop-core.ide_uri
  description = "Windsurf Editor URL."
}