terraform {
  required_version = ">= 1.0"
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
  default     = ""
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  mcp_b64 = var.mcp != "" ? base64encode(var.mcp) : ""
}

module "vscode-desktop-core" {
  source = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.0"
  
  agent_id = var.agent_id

  web_app_icon         = "/icon/windsurf.svg"
  web_app_slug         = "windsurf"
  web_app_display_name = "Windsurf Editor"
  web_app_order        = var.order
  web_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "windsurf"
}

resource "coder_script" "windsurf_mcp" {
  count              = var.mcp != "" ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Windsurf MCP"
  icon               = "/icon/windsurf.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -eu
    mkdir -p "$HOME/.codeium/windsurf"
    echo -n "${local.mcp_b64}" | base64 -d > "$HOME/.codeium/windsurf/mcp_config.json"
    chmod 600 "$HOME/.codeium/windsurf/mcp_config.json"
  EOT
}

output "windsurf_url" {
  value       = module.windsurf.ide_uri
  description = "Windsurf Editor URL."
}