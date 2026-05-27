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
  description = "The ID of a Coder agent."
  type        = string
}

variable "folder" {
  description = "The folder to open in Trae CN."
  type        = string
  default     = ""
}

variable "open_recent" {
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  type        = bool
  default     = false
}

variable "order" {
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to."
  type        = string
  default     = null
}

variable "slug" {
  description = "The slug of the app."
  type        = string
  default     = "trae-cn"
}

variable "display_name" {
  description = "The display name of the app."
  type        = string
  default     = "Trae CN"
}

variable "mcp" {
  description = "JSON-encoded string to configure MCP servers for Trae CN. When set, writes mcp_config_path."
  type        = string
  default     = ""
}

variable "mcp_config_path" {
  description = "Path to write the Trae CN MCP configuration. Defaults to folder/.trae/mcp.json when folder is set, otherwise $HOME/.trae/mcp.json."
  type        = string
  default     = ""
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  mcp_b64 = var.mcp != "" ? base64encode(var.mcp) : ""
  mcp_config_path = (
    var.mcp_config_path != ""
    ? var.mcp_config_path
    : var.folder != ""
    ? "${var.folder}/.trae/mcp.json"
    : "$HOME/.trae/mcp.json"
  )
  mcp_config_path_b64 = base64encode(local.mcp_config_path)
}

module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.2"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/trae-cn.png"
  coder_app_slug         = var.slug
  coder_app_display_name = var.display_name
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "trae-cn"
}

resource "coder_script" "trae_cn_mcp" {
  count              = var.mcp != "" ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Trae CN MCP"
  icon               = "/icon/trae-cn.png"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -eu

    mcp_config_path="$(echo -n '${local.mcp_config_path_b64}' | base64 -d)"
    case "$mcp_config_path" in
      "\$HOME/"*) mcp_config_path="$HOME/$${mcp_config_path#\$HOME/}" ;;
      "~/"*) mcp_config_path="$HOME/$${mcp_config_path#~/}" ;;
    esac

    mkdir -p "$(dirname "$mcp_config_path")"
    echo -n '${local.mcp_b64}' | base64 -d > "$mcp_config_path"
    chmod 600 "$mcp_config_path"
  EOT
}

output "trae_cn_url" {
  description = "Trae CN URL."
  value       = module.vscode-desktop-core.ide_uri
}
