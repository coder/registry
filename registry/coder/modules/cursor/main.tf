terraform {
  required_version = ">= 1.0"
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "folder" {
  type        = string
  description = "The folder to open in Cursor IDE."
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
  default     = "cursor"
}

variable "display_name" {
  type        = string
  description = "The display name of the app."
  default     = "Cursor Desktop"
}

variable "mcp" {
  type        = string
  description = "JSON-encoded string to configure MCP servers for Cursor. When set, writes ~/.cursor/mcp.json."
  default     = ""
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  mcp_b64 = var.mcp != "" ? base64encode(var.mcp) : ""
}

module "cursor" {
  # TODO: update this
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/vscode-desktop-core?ref=phorcys420/centralize-vscode-desktop"

  agent_id = var.agent_id

  web_app_icon         = "/icon/cursor.svg"
  web_app_slug         = var.slug
  web_app_display_name = var.display_name
  web_app_order        = var.order
  web_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "cursor"
}

resource "coder_script" "cursor_mcp" {
  count              = var.mcp != "" ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Cursor MCP"
  icon               = "/icon/cursor.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -eu
    mkdir -p "$HOME/.cursor"
    echo -n "${local.mcp_b64}" | base64 -d > "$HOME/.cursor/mcp.json"
    chmod 600 "$HOME/.cursor/mcp.json"
  EOT
}

output "cursor_url" {
  value       = module.cursor.ide_uri
  description = "Cursor IDE Desktop URL."
}