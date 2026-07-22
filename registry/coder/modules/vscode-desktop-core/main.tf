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
  description = "MCP server configuration for the IDE. When set, writes mcp_config.json in var.config_dir."
  default     = null
}

variable "extensions" {
  description = "Extension IDs to pre-install on the remote workspace host."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for extension in var.extensions : trimspace(extension) != ""])
    error_message = "extensions must not contain empty extension IDs."
  }
}

variable "extensions_dir" {
  description = "Remote extension directory supplied by the IDE wrapper."
  type        = string
  default     = ""
}

variable "ide_cli_path" {
  description = "Remote IDE server CLI supplied by the IDE wrapper."
  type        = string
  default     = ""
}

variable "ide_cli_install_script" {
  description = "Internal wrapper-provided finite script that makes ide_cli_path available."
  type        = string
  default     = null
}

variable "protocol" {
  type        = string
  description = "The URI protocol the IDE."
}

variable "config_dir" {
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

locals {
  install_extensions_script = length(var.extensions) > 0 ? templatefile(
    "${path.module}/scripts/install-extensions.sh.tftpl",
    {
      IDE_CLI_INSTALL_SCRIPT_B64 = var.ide_cli_install_script != null ? base64encode(var.ide_cli_install_script) : ""
      EXTENSIONS_B64_LINES       = join("\n", [for extension in var.extensions : base64encode(extension)])
      EXTENSIONS_DIR_B64         = base64encode(var.extensions_dir)
      IDE_CLI_PATH_B64           = base64encode(var.ide_cli_path)
    },
  ) : ""
}

resource "coder_script" "install_extensions" {
  count              = length(var.extensions) > 0 ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "${var.coder_app_display_name} Extensions"
  icon               = var.coder_app_icon
  run_on_start       = true
  start_blocks_login = true
  timeout            = 1800
  script             = local.install_extensions_script
}

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

    IDE_CONFIG_FOLDER="${var.config_dir}"
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
