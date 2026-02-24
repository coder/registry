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
  description = "The folder to open in the IDE."
  default     = ""
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
}

variable "mcp_config" {
  type        = map(any)
  description = "MCP server configuration for the IDE. When set, writes mcp_config.json in var.config_folder."
  default     = null
}

variable "protocol" {
  type        = string
  description = "The URI protocol the IDE."
}

variable "config_folder" {
  type        = string
  description = "The path of the IDE's configuration folder."
}

variable "coder_app_icon" {
  type        = string
  description = "The icon of the coder_app."
}

variable "coder_app_slug" {
  type        = string
  description = "The slug of the coder_app."
}

variable "coder_app_display_name" {
  type        = string
  description = "The display name of the coder_app."
}

variable "coder_app_order" {
  type        = number
  description = "The order of the coder_app."
  default     = null
}

variable "coder_app_group" {
  type        = string
  description = "The group of the coder_app."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "vscode-desktop" {
  agent_id = var.agent_id
  external = true

  icon         = var.coder_app_icon
  slug         = var.coder_app_slug
  display_name = var.coder_app_display_name

  order = var.coder_app_order
  group = var.coder_app_group

  url = join("", [
    var.protocol,
    "://coder.coder-remote/open",
    "?owner=",
    data.coder_workspace_owner.me.name,
    "&workspace=",
    data.coder_workspace.me.name,
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])
}

resource "coder_script" "vscode-desktop-mcp" {
  agent_id = var.agent_id
  count    = var.mcp_config != null ? 1 : 0

  icon         = var.coder_app_icon
  display_name = "${var.coder_app_display_name} MCP"

  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/sh
    set -euo pipefail

    IDE_CONFIG_FOLDER="${var.config_folder}"
    IDE_MCP_CONFIG_PATH="$IDE_CONFIG_FOLDER/mcp_config.json"

    mkdir -p "$IDE_CONFIG_FOLDER"

    echo -n "${base64encode(jsonencode(var.mcp_config))}" | base64 -d > "$IDE_MCP_CONFIG_PATH"
    chmod 600 "$IDE_MCP_CONFIG_PATH"

    # Cursor/Windsurf use this config instead, no need for chmod as symlinks do not have modes
    ln -s "$IDE_MCP_CONFIG_PATH" "$IDE_CONFIG_FOLDER/mcp.json"
  EOT
}

output "ide_uri" {
  value       = coder_app.vscode-desktop.url
  description = "IDE URI."
}
