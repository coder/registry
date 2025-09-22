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
  default     = "/icon/claude.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run Claude Code in."
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via AgentAPI"
  default     = true
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for Claude Code"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Claude Code"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "Claude Code CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Claude Code."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Claude Code."
  default     = null
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

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for Claude Code."
  default     = ""
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}


variable "install_claude_code" {
  type        = bool
  description = "Whether to install Claude Code."
  default     = true
}

variable "claude_code_version" {
  type        = string
  description = "The version of Claude Code to install."
  default     = "latest"
}

variable "claude_api_key" {
  type        = string
  description = "The API key to use for the Claude Code server."
  default     = ""
}

variable "model" {
  type        = string
  description = "Sets the model for the current session with an alias for the latest model (sonnet or opus) or a model’s full name."
  default     = ""
}

variable "resume_session_id" {
  type        = string
  description = "Resume a specific session by ID."
  default     = ""
}

variable "continue" {
  type        = bool
  description = "Load the most recent conversation in the current directory. Task will fail in a new workspace with no conversation/session to continue"
  default     = false
}

variable "dangerously_skip_permissions" {
  type        = bool
  description = "Skip the permission prompts. Use with caution. This will be set to true if using Coder Tasks"
  default     = false
}

variable "permission_mode" {
  type        = string
  description = "Permission mode for the cli, check https://docs.anthropic.com/en/docs/claude-code/iam#permission-modes"
  default     = ""
  validation {
    condition     = contains(["", "default", "acceptEdits", "plan", "bypassPermissions"], var.permission_mode)
    error_message = "interaction_mode must be one of: default, acceptEdits, plan, bypassPermissions."
  }
}

variable "mcp" {
  type        = string
  description = "MCP JSON to be added to the claude code local scope"
  default     = ""
}

variable "allowed_tools" {
  type        = string
  description = "A list of tools that should be allowed without prompting the user for permission, in addition to settings.json files."
  default     = ""
}

variable "disallowed_tools" {
  type        = string
  description = "A list of tools that should be disallowed without prompting the user for permission, in addition to settings.json files."
  default     = ""

}

variable "claude_code_oauth_token" {
  type        = string
  description = "Set up a long-lived authentication token (requires Claude subscription). Generated using `claude setup-token` command"
  sensitive   = true
  default     = ""
}

variable "system_prompt" {
  type        = string
  description = "The system prompt to use for the Claude Code server."
  default     = "Send a task status update to notify the user that you are ready for input, and then wait for user input."
}

variable "claude_md_path" {
  type        = string
  description = "The path to CLAUDE.md."
  default     = "$HOME/.claude/CLAUDE.md"
}

resource "coder_env" "claude_code_md_path" {
  count = var.claude_md_path == "" ? 0 : 1

  agent_id = var.agent_id
  name     = "CODER_MCP_CLAUDE_MD_PATH"
  value    = var.claude_md_path
}

resource "coder_env" "claude_code_system_prompt" {
  count = var.system_prompt == "" ? 0 : 1

  agent_id = var.agent_id
  name     = "CODER_MCP_CLAUDE_SYSTEM_PROMPT"
  value    = var.system_prompt
}

resource "coder_env" "claude_code_oauth_token" {
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "claude_api_key" {
  count = length(var.claude_api_key) > 0 ? 1 : 0

  agent_id = var.agent_id
  name     = "CLAUDE_API_KEY"
  value    = var.claude_api_key
}

locals {
  # we have to trim the slash because otherwise coder exp mcp will
  # set up an invalid claude config 
  workdir                           = trimsuffix(var.workdir, "/")
  app_slug                          = "ccw"
  install_script                    = file("${path.module}/scripts/install.sh")
  start_script                      = file("${path.module}/scripts/start.sh")
  module_dir_name                   = ".claude-module"
  remove_last_session_id_script_b64 = base64encode(file("${path.module}/scripts/remove-last-session-id.sh"))
}

module "agentapi" {

  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
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
  start_script         = <<-EOT
     #!/bin/bash
     set -o errexit
     set -o pipefail
     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
     echo -n "${local.remove_last_session_id_script_b64}" | base64 -d > "/tmp/remove-last-session-id.sh"
     chmod +x /tmp/start.sh
     chmod +x /tmp/remove-last-session-id.sh

     ARG_MODEL='${var.model}' \
     ARG_RESUME_SESSION_ID='${var.resume_session_id}' \
     ARG_CONTINUE='${var.continue}' \
     ARG_DANGEROUSLY_SKIP_PERMISSIONS='${var.dangerously_skip_permissions}' \
     ARG_PERMISSION_MODE='${var.permission_mode}' \
     ARG_WORKDIR='${local.workdir}' \
     ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_CLAUDE_CODE_VERSION='${var.claude_code_version}' \
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_INSTALL_CLAUDE_CODE='${var.install_claude_code}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_WORKDIR='${local.workdir}' \
    ARG_ALLOWED_TOOLS='${var.allowed_tools}' \
    ARG_DISALLOWED_TOOLS='${var.disallowed_tools}' \
    ARG_MCP='${var.mcp != null ? base64encode(replace(var.mcp, "'", "'\\''")) : ""}' \
    /tmp/install.sh
  EOT
}
