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

variable "workdir" {
  type        = string
  description = "The folder to run Copilot CLI in."
}

variable "external_auth_id" {
  type        = string
  description = "ID of the GitHub external auth provider configured in Coder."
  default     = "github"
}

variable "copilot_model" {
  type        = string
  description = "Model to use. Supported values: claude-sonnet-4 (default), claude-sonnet-4.5, gpt-5."
  default     = "claude-sonnet-4"
  validation {
    condition     = contains(["claude-sonnet-4", "claude-sonnet-4.5", "gpt-5"], var.copilot_model)
    error_message = "copilot_model must be one of: claude-sonnet-4, claude-sonnet-4.5, gpt-5."
  }
}

variable "copilot_config" {
  type        = string
  description = "Custom Copilot CLI configuration as JSON string. Leave empty to use default configuration with banner disabled, theme set to auto, and workdir as trusted folder."
  default     = ""
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for programmatic mode."
  default     = ""
}

variable "system_prompt" {
  type        = string
  description = "The system prompt to use for the Copilot CLI server."
  default     = "You are a helpful AI assistant that helps with coding tasks. Always provide clear explanations and follow best practices. Send a task status update to notify the user that you are ready for input, and then wait for user input."
}

variable "trusted_directories" {
  type        = list(string)
  description = "Additional directories to trust for Copilot CLI operations."
  default     = []
}

variable "allow_all_tools" {
  type        = bool
  description = "Allow all tools without prompting (equivalent to --allow-all-tools)."
  default     = false
}

variable "allow_tools" {
  type        = list(string)
  description = "Specific tools to allow: shell(command), write, or MCP_SERVER_NAME."
  default     = []
}

variable "deny_tools" {
  type        = list(string)
  description = "Specific tools to deny: shell(command), write, or MCP_SERVER_NAME."
  default     = []
}

variable "mcp_config" {
  type        = string
  description = "Custom MCP server configuration as JSON string."
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
  default     = "v0.7.1"
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via AgentAPI."
  default     = true
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
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
  default     = "/icon/github.svg"
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app."
  default     = "Copilot CLI"
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for Copilot CLI."
  default     = false
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app."
  default     = "Copilot CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before configuring Copilot CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after configuring Copilot CLI."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_external_auth" "github" {
  id = var.external_auth_id
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "copilot-cli"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".copilot-module"

  # Default configuration with workdir as trusted folder
  default_copilot_config = jsonencode({
    banner          = "never"
    theme           = "auto"
    trusted_folders = concat([local.workdir], var.trusted_directories)
  })

  final_copilot_config = var.copilot_config != "" ? var.copilot_config : local.default_copilot_config
}

resource "coder_env" "mcp_app_status_slug" {
  agent_id = var.agent_id
  name     = "CODER_MCP_APP_STATUS_SLUG"
  value    = local.app_slug
}

resource "coder_env" "copilot_model" {
  count    = var.copilot_model != "claude-sonnet-4" ? 1 : 0
  agent_id = var.agent_id
  name     = "COPILOT_MODEL"
  value    = var.copilot_model
}



module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
  folder               = local.workdir
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = var.web_app_display_name
  cli_app              = var.cli_app
  cli_app_slug         = var.cli_app ? "${local.app_slug}-cli" : null
  cli_app_display_name = var.cli_app ? var.cli_app_display_name : null
  agentapi_subdomain   = var.subdomain
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script

  start_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
    chmod +x /tmp/start.sh
    
    ARG_WORKDIR='${local.workdir}' \
    ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
    ARG_SYSTEM_PROMPT='${base64encode(var.system_prompt)}' \
    ARG_COPILOT_MODEL='${var.copilot_model}' \
    ARG_ALLOW_ALL_TOOLS='${var.allow_all_tools}' \
    ARG_ALLOW_TOOLS='${join(",", var.allow_tools)}' \
    ARG_DENY_TOOLS='${join(",", var.deny_tools)}' \
    ARG_TRUSTED_DIRECTORIES='${join(",", var.trusted_directories)}' \
    /tmp/start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_WORKDIR='${local.workdir}' \
    ARG_MCP_CONFIG='${var.mcp_config != "" ? base64encode(var.mcp_config) : ""}' \
    ARG_COPILOT_CONFIG='${base64encode(local.final_copilot_config)}' \
    ARG_EXTERNAL_AUTH_ID='${var.external_auth_id}' \
    /tmp/install.sh
  EOT
}