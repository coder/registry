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
  default     = "/icon/openai.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run Codex in."
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via AgentAPI"
  default     = true
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for Codex"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Codex"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "Codex CLI"
}

variable "enable_aibridge" {
  type        = bool
  description = "Use AI Bridge for Codex. https://coder.com/docs/ai-coder/ai-bridge"
  default     = false

  validation {
    condition     = !(var.enable_aibridge && length(var.openai_api_key) > 0)
    error_message = "openai_api_key cannot be provided when enable_aibridge is true. AI Bridge automatically authenticates the client using their Coder credentials."
  }
}

variable "model_reasoning_effort" {
  type        = string
  description = "The reasoning effort for the AI Bridge model. One of: none, low, medium, high. https://platform.openai.com/docs/guides/latest-model#lower-reasoning-effort"
  default     = "medium"
  validation {
    condition     = contains(["none", "low", "medium", "high"], var.model_reasoning_effort)
    error_message = "model_reasoning_effort must be one of: none, low, medium, high."
  }
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
  default     = "v0.11.6"
}

variable "codex_model" {
  type        = string
  description = "The model for Codex to use. Defaults to gpt-5.2-codex."
  default     = "gpt-5.2-codex"
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

variable "continue" {
  type        = bool
  description = "Automatically continue existing sessions on workspace restart. When true, resumes existing conversation if found, otherwise runs prompt or starts new session. When false, always starts fresh (ignores existing sessions)."
  default     = true
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

resource "coder_env" "coder_aibridge_session_token" {
  count    = var.enable_aibridge ? 1 : 0
  agent_id = var.agent_id
  name     = "CODER_AIBRIDGE_SESSION_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "codex"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".codex-module"
  aibridge_config = <<-EOF
  [model_providers.aibridge]
  name = "AI Bridge"
  base_url = "${data.coder_workspace.me.access_url}/api/v2/aibridge/openai/v1"
  env_key = "CODER_AIBRIDGE_SESSION_TOKEN"
  wire_api = "responses"

  [profiles.aibridge]
  model_provider = "aibridge"
  model = "${var.codex_model}"
  model_reasoning_effort = "${var.model_reasoning_effort}"
  EOF
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "2.0.0"

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
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_subdomain   = var.subdomain
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
     ARG_REPORT_TASKS='${var.report_tasks}' \
     ARG_CODEX_MODEL='${var.codex_model}' \
     ARG_CODEX_START_DIRECTORY='${local.workdir}' \
     ARG_CODEX_TASK_PROMPT='${base64encode(var.ai_prompt)}' \
     ARG_CONTINUE='${var.continue}' \
     ARG_ENABLE_AIBRIDGE='${var.enable_aibridge}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_OPENAI_API_KEY='${var.openai_api_key}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_INSTALL='${var.install_codex}' \
    ARG_CODEX_VERSION='${var.codex_version}' \
    ARG_BASE_CONFIG_TOML='${base64encode(var.base_config_toml)}' \
    ARG_ENABLE_AIBRIDGE='${var.enable_aibridge}' \
    ARG_AIBRIDGE_CONFIG='${base64encode(var.enable_aibridge ? local.aibridge_config : "")}' \
    ARG_ADDITIONAL_MCP_SERVERS='${base64encode(var.additional_mcp_servers)}' \
    ARG_CODER_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_CODEX_START_DIRECTORY='${local.workdir}' \
    ARG_CODEX_INSTRUCTION_PROMPT='${base64encode(var.codex_system_prompt)}' \
    /tmp/install.sh
  EOT
}

output "task_app_id" {
  value = module.agentapi.task_app_id
}
