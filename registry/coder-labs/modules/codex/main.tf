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
  default     = "/icon/openai.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Codex in."
}

variable "install_codex" {
  type        = bool
  description = "Whether to install Codex."
  default     = true
}

variable "codex_version" {
  type        = string
  description = "The version of Codex to install."
  default     = "" # empty string means the latest available version
}

variable "base_config_toml" {
  type        = string
  description = "Complete base TOML configuration for Codex (without mcp_servers section). If empty, uses minimal default configuration with workspace-write sandbox mode and never approval policy. For advanced options, see https://github.com/openai/codex/blob/main/codex-rs/config.md"
  default     = ""
}

variable "additional_mcp_servers" {
  type        = string
  description = "Additional MCP servers configuration in TOML format. These will be merged with the required Coder MCP server in the [mcp_servers] section."
  default     = ""
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key for Codex CLI"
  default     = ""
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

variable "codex_model" {
  type        = string
  description = "The model for Codex to use. Defaults to gpt-5."
  default     = ""
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Codex."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Codex."
  default     = null
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for Codex CLI when launched via Tasks"
  default     = ""
}

variable "codex_system_prompt" {
  type        = string
  description = "System instructions written to AGENTS.md in the ~/.codex directory"
  default     = "You are a helpful coding assistant. Start every response with `Codex says:`"
}

resource "coder_env" "openai_api_key" {
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

locals {
  app_slug        = "codex"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".codex-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Codex"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Codex CLI"
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
     ARG_OPENAI_API_KEY='${var.openai_api_key}' \
     ARG_CODEX_MODEL='${var.codex_model}' \
     ARG_CODEX_START_DIRECTORY='${var.folder}' \
     ARG_CODEX_TASK_PROMPT='${base64encode(var.ai_prompt)}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_codex}' \
    ARG_CODEX_VERSION='${var.codex_version}' \
    ARG_BASE_CONFIG_TOML='${base64encode(var.base_config_toml)}' \
    ARG_ADDITIONAL_MCP_SERVERS='${base64encode(var.additional_mcp_servers)}' \
    ARG_CODER_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_CODEX_START_DIRECTORY='${var.folder}' \
    ARG_CODEX_INSTRUCTION_PROMPT='${base64encode(var.codex_system_prompt)}' \
    /tmp/install.sh
  EOT
}