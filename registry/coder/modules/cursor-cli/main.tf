terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

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

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/cursor.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Cursor CLI in."
  default     = "/home/coder"
}

variable "install_cursor_cli" {
  type        = bool
  description = "Whether to install Cursor CLI."
  default     = true
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.3.3"
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = true
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Cursor CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Cursor CLI."
  default     = null
}

variable "enable_mcp" {
  type        = bool
  description = "Whether to enable MCP (Model Context Protocol) support."
  default     = true
}

variable "mcp_config_path" {
  type        = string
  description = "Path to the MCP configuration file (mcp.json)."
  default     = ""
}

variable "enable_force_mode" {
  type        = bool
  description = "Whether to enable force mode for non-interactive automation."
  default     = false
}

variable "default_model" {
  type        = string
  description = "Default AI model to use (e.g., gpt-5, claude-4-sonnet)."
  default     = ""
}

variable "enable_rules" {
  type        = bool
  description = "Whether to enable the rules system (.cursor/rules directory)."
  default     = true
}

locals {
  app_slug           = "cursor-cli"
  install_script     = file("${path.module}/scripts/install.sh")
  start_script       = file("${path.module}/scripts/start.sh")
  module_dir_name    = ".cursor-cli-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Cursor CLI"
  cli_app_slug         = "${local.app_slug}-terminal"
  cli_app_display_name = "Cursor CLI Terminal"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  agentapi_subdomain   = var.subdomain
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_FOLDER='${var.folder}' \
    ARG_INSTALL='${var.install_cursor_cli}' \
    ARG_ENABLE_MCP='${var.enable_mcp}' \
    ARG_MCP_CONFIG_PATH='${var.mcp_config_path}' \
    ARG_ENABLE_FORCE_MODE='${var.enable_force_mode}' \
    ARG_DEFAULT_MODEL='${var.default_model}' \
    ARG_ENABLE_RULES='${var.enable_rules}' \
    /tmp/install.sh
  EOT
}
