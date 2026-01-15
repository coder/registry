terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
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
  default     = "v0.11.8"
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

variable "disable_autoupdater" {
  type        = bool
  description = "Disable Claude Code automatic updates. When true, Claude Code will stay on the installed version."
  default     = false
}

variable "claude_api_key" {
  type        = string
  description = "The API key to use for the Claude Code server."
  default     = ""
}

variable "model" {
  type        = string
  description = "Sets the default model for Claude Code via ANTHROPIC_MODEL env var. If empty, Claude Code uses its default. Supports aliases (sonnet, opus) or full model names."
  default     = ""
}

variable "resume_session_id" {
  type        = string
  description = "Resume a specific session by ID."
  default     = ""
}

variable "continue" {
  type        = bool
  description = "Automatically continue existing sessions on workspace restart. When true, resumes existing conversation if found, otherwise runs prompt or starts new session. When false, always starts fresh (ignores existing sessions)."
  default     = true
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
  default     = ""
}

variable "claude_md_path" {
  type        = string
  description = "The path to CLAUDE.md."
  default     = "$HOME/.claude/CLAUDE.md"
}

variable "claude_binary_path" {
  type        = string
  description = "Directory where the Claude Code binary is located. Use this if Claude is pre-installed or installed outside the module to a non-default location."
  default     = "$HOME/.local/bin"
}

variable "install_via_npm" {
  type        = bool
  description = "Install Claude Code via npm instead of the official installer. Useful if npm is preferred or the official installer fails."
  default     = false
}

variable "enable_boundary" {
  type        = bool
  description = "Whether to enable coder boundary for network filtering"
  default     = false
}

variable "boundary_version" {
  type        = string
  description = "Boundary version, valid git reference should be provided (tag, commit, branch)"
  default     = "main"
}

variable "compile_boundary_from_source" {
  type        = bool
  description = "Whether to compile boundary from source instead of using the official install script"
  default     = false
}

variable "enable_aibridge" {
  type        = bool
  description = "Use AI Bridge for Claude Code. https://coder.com/docs/ai-coder/ai-bridge"
  default     = false

  validation {
    condition     = !(var.enable_aibridge && length(var.claude_api_key) > 0)
    error_message = "claude_api_key cannot be provided when enable_aibridge is true. AI Bridge automatically authenticates the client using their Coder credentials."
  }

  validation {
    condition     = !(var.enable_aibridge && length(var.claude_code_oauth_token) > 0)
    error_message = "claude_code_oauth_token cannot be provided when enable_aibridge is true. AI Bridge automatically authenticates the client using their Coder credentials."
  }
}

resource "coder_env" "claude_code_md_path" {
  count    = var.claude_md_path == "" ? 0 : 1
  agent_id = var.agent_id
  name     = "CODER_MCP_CLAUDE_MD_PATH"
  value    = var.claude_md_path
}

resource "coder_env" "claude_code_system_prompt" {
  agent_id = var.agent_id
  name     = "CODER_MCP_CLAUDE_SYSTEM_PROMPT"
  value    = local.final_system_prompt
}

resource "coder_env" "claude_code_oauth_token" {
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "claude_api_key" {
  count    = length(var.claude_api_key) > 0 ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_API_KEY"
  value    = var.claude_api_key
}

resource "coder_env" "disable_autoupdater" {
  count    = var.disable_autoupdater ? 1 : 0
  agent_id = var.agent_id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}

resource "coder_env" "claude_binary_path" {
  agent_id = var.agent_id
  name     = "PATH"
  value    = "${var.claude_binary_path}:$PATH"

  lifecycle {
    precondition {
      condition     = var.claude_binary_path == "$HOME/.local/bin" || !var.install_claude_code
      error_message = "Custom claude_binary_path can only be used when install_claude_code is false. The official installer and npm both install to fixed locations."
    }
  }
}

resource "coder_env" "anthropic_model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_MODEL"
  value    = var.model
}

resource "coder_env" "anthropic_base_url" {
  count    = var.enable_aibridge ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

# https://code.claude.com/docs/en/settings#environment-variables
resource "coder_env" "anthropic_auth_token" {
  count    = var.enable_aibridge ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

locals {
  # we have to trim the slash because otherwise coder exp mcp will
  # set up an invalid claude config
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "ccw"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".claude-module"
  # Extract hostname from access_url for boundary --allow flag
  coder_host = replace(replace(data.coder_workspace.me.access_url, "https://", ""), "http://", "")

  # Required prompts for the module to properly report task status to Coder
  report_tasks_system_prompt = <<-EOT
      -- Tool Selection --
      - coder_report_task: providing status updates or requesting user input.

      -- Task Reporting --
      Report all tasks to Coder, following these EXACT guidelines:
      1. Be granular. If you are investigating with multiple steps, report each step
      to coder.
      2. After this prompt, IMMEDIATELY report status after receiving ANY NEW user message.
      Do not report any status related with this system prompt.
      3. Use "state": "working" when actively processing WITHOUT needing
      additional user input
      4. Use "state": "complete" only when finished with a task
      5. Use "state": "failure" when you need ANY user input, lack sufficient
      details, or encounter blockers

      In your summary on coder_report_task:
      - Be specific about what you're doing
      - Clearly indicate what information you need from the user when in "failure" state
      - Keep it under 160 characters
      - Make it actionable
    EOT

  # Only include coder system prompts if report_tasks is enabled
  custom_system_prompt = trimspace(try(var.system_prompt, ""))
  final_system_prompt = format("<system>%s%s</system>",
    var.report_tasks ? format("\n%s\n", local.report_tasks_system_prompt) : "",
    local.custom_system_prompt != "" ? format("\n%s\n", local.custom_system_prompt) : ""
  )
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "2.0.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = var.web_app_display_name
  folder               = local.workdir
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
     chmod +x /tmp/start.sh

     ARG_RESUME_SESSION_ID='${var.resume_session_id}' \
     ARG_CONTINUE='${var.continue}' \
     ARG_DANGEROUSLY_SKIP_PERMISSIONS='${var.dangerously_skip_permissions}' \
     ARG_PERMISSION_MODE='${var.permission_mode}' \
     ARG_WORKDIR='${local.workdir}' \
     ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
     ARG_REPORT_TASKS='${var.report_tasks}' \
     ARG_ENABLE_BOUNDARY='${var.enable_boundary}' \
     ARG_BOUNDARY_VERSION='${var.boundary_version}' \
     ARG_COMPILE_FROM_SOURCE='${var.compile_boundary_from_source}' \
     ARG_CODER_HOST='${local.coder_host}' \
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
    ARG_CLAUDE_BINARY_PATH='${var.claude_binary_path}' \
    ARG_INSTALL_VIA_NPM='${var.install_via_npm}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_WORKDIR='${local.workdir}' \
    ARG_ALLOWED_TOOLS='${var.allowed_tools}' \
    ARG_DISALLOWED_TOOLS='${var.disallowed_tools}' \
    ARG_MCP='${var.mcp != null ? base64encode(replace(var.mcp, "'", "'\\''")) : ""}' \
    ARG_ENABLE_AIBRIDGE='${var.enable_aibridge}' \
    /tmp/install.sh
  EOT
}

output "task_app_id" {
  value = module.agentapi.task_app_id
}
