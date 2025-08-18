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
  default     = "v0.5.0"
}

variable "force" {
  type        = bool
  description = "Force allow commands unless explicitly denied"
  default     = true
}

variable "model" {
  type        = string
  description = "Model to use (e.g., sonnet-4, sonnet-4-thinking, gpt-5)"
  default     = ""
}

variable "ai_prompt" {
  type        = string
  description = "AI prompt/task passed to cursor-agent."
  default     = ""
}

variable "api_key" {
  type        = string
  description = "API key for Cursor CLI."
  default     = ""
  sensitive   = true
}

variable "mcp" {
  type        = string
  description = "Workspace-specific MCP JSON to write to folder/.cursor/mcp.json. See https://docs.cursor.com/en/context/mcp#using-mcp-json"
  default     = null
}

variable "rules_files" {
  type        = map(string)
  description = "Optional map of rule file name to content. Files will be written to folder/.cursor/rules/<name>. See https://docs.cursor.com/en/context/rules#project-rules"
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Optional script to run before installing Cursor CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Optional script to run after installing Cursor CLI."
  default     = null
}

locals {
  app_slug        = "cursorcli"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".cursor-cli-module"
}

# Expose status slug and API key to the agent environment
resource "coder_env" "status_slug" {
  agent_id = var.agent_id
  name     = "CODER_MCP_APP_STATUS_SLUG"
  value    = local.app_slug
}

resource "coder_env" "cursor_api_key" {
  count    = var.api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CURSOR_API_KEY"
  value    = var.api_key
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Cursor CLI"
  cli_app_slug         = local.app_slug
  cli_app_display_name = "Cursor CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = <<-EOT
     #!/bin/bash
     set -o errexit
     set -o pipefail

     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
     chmod +x /tmp/start.sh
      ARG_FORCE='${var.force}' \
      ARG_MODEL='${var.model}' \
      ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
      ARG_MODULE_DIR_NAME='${local.module_dir_name}' \
      ARG_FOLDER='${var.folder}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_cursor_cli}' \
    ARG_WORKSPACE_MCP_JSON='${var.mcp != null ? base64encode(replace(var.mcp, "'", "'\\''")) : ""}' \
    ARG_WORKSPACE_RULES_JSON='${var.rules_files != null ? base64encode(jsonencode(var.rules_files)) : ""}' \
    ARG_MODULE_DIR_NAME='${local.module_dir_name}' \
    ARG_FOLDER='${var.folder}' \
    ARG_CODER_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    /tmp/install.sh
  EOT
}
