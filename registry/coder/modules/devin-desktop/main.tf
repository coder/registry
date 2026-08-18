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
  description = "The folder to open in Devin Desktop."
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
  default     = "devin-desktop"
}

variable "display_name" {
  type        = string
  description = "The display name of the app."
  default     = "Devin Desktop"
}

variable "mcp" {
  type        = string
  description = "JSON-encoded string to configure MCP servers for Devin Desktop. When set, writes ~/.codeium/windsurf/mcp_config.json, the path Devin Desktop inherited from Windsurf."
  default     = ""
}

variable "protocol" {
  type        = string
  description = "The URI protocol used to open Devin Desktop. Defaults to the devin:// scheme."
  default     = "devin"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  mcp_b64 = var.mcp != "" ? base64encode(var.mcp) : ""
}

# Devin Desktop is Cognition's rebrand of the Windsurf Editor (June 2, 2026),
# which was itself Codeium's rebrand of its original editor. It uses the same
# VS Code Desktop launch mechanism as the windsurf module, so this wraps the
# same shared vscode-desktop-core module with Devin Desktop's branding.
module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.2"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/devin.svg"
  coder_app_slug         = var.slug
  coder_app_display_name = var.display_name
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  # devin:// is registered as an external app protocol in coder/coder
  # (ALLOWED_EXTERNAL_APP_PROTOCOLS, coder/coder#28214).
  protocol = var.protocol
}

resource "coder_script" "devin_desktop_mcp" {
  count              = var.mcp != "" ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Devin Desktop MCP"
  icon               = "/icon/devin.svg"
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

output "devin_desktop_url" {
  value       = module.vscode-desktop-core.ide_uri
  description = "Devin Desktop URL."
}
