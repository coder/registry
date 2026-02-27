terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
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
  default     = "/icon/sourcegraph-amp.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run AMP CLI in."
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.11.1"
}

variable "agentapi_cache_dir" {
  type        = string
  description = "Path to a directory where the AgentAPI binary will be cached after download. On subsequent workspace starts, the cached binary is used instead of downloading again."
  default     = ""
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for Claude Code"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Amp"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "Amp CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing amp cli"
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing amp cli."
  default     = null
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI"
  default     = true
}

variable "install_amp" {
  type        = bool
  description = "Whether to install amp cli."
  default     = true
}

variable "install_via_npm" {
  type        = bool
  description = "Install Amp via npm instead of the official installer."
  default     = false
}

variable "amp_api_key" {
  type        = string
  description = "amp cli API Key"
  default     = ""
}

variable "amp_version" {
  type        = string
  description = "The version of amp cli to install."
  default     = ""
}

variable "ai_prompt" {
  type        = string
  description = "Task prompt for the Amp CLI"
  default     = ""
}

variable "instruction_prompt" {
  type        = string
  description = "Instruction prompt for the Amp CLI. https://ampcode.com/manual#AGENTS.md"
  default     = ""
}

resource "coder_env" "amp_api_key" {
  agent_id = var.agent_id
  name     = "AMP_API_KEY"
  value    = var.amp_api_key
}

variable "base_amp_config" {
  type        = string
  description = <<-EOT
    Base AMP configuration in JSON format. Can be overridden to customize AMP settings.

    If empty, defaults enable thinking and todos for autonomous operation. Additional options include:
    - "amp.permissions": [] (tool permissions)
    - "amp.tools.stopTimeout": 600 (extend timeout for long operations)
    - "amp.terminal.commands.nodeSpawn.loadProfile": "daily" (environment loading)
    - "amp.tools.disable": ["builtin:open"] (disable tools for containers)
    - "amp.git.commit.ampThread.enabled": true (link commits to threads)
    - "amp.git.commit.coauthor.enabled": true (add Amp as co-author)

    Reference: https://ampcode.com/manual
  EOT
  default     = ""
}

variable "mcp" {
  type        = string
  description = "Additional MCP servers configuration in JSON format to append to amp.mcpServers."
  default     = null
}

variable "mode" {
  type        = string
  description = "Set the agent mode (free, rush, smart) — controls the model, system prompt, and tool selection. Default: smart"
  default     = "smart"
  validation {
    condition     = contains(["", "free", "rush", "smart"], var.mode)
    error_message = "Invalid mode. Select one from (free, rush, smart)"
  }
}

data "external" "env" {
  program = ["sh", "-c", "echo '{\"CODER_AGENT_TOKEN\":\"'$CODER_AGENT_TOKEN'\",\"CODER_AGENT_URL\":\"'$CODER_AGENT_URL'\"}'"]
}

locals {
  app_slug = "amp"

  default_base_config = jsonencode({
    "amp.anthropic.thinking.enabled" = true
    "amp.todos.enabled"              = true
    "amp.terminal.animation"         = false
  })

  user_config       = jsondecode(var.base_amp_config != "" ? var.base_amp_config : local.default_base_config)
  base_amp_settings = { for k, v in local.user_config : k => v if k != "amp.mcpServers" }

  coder_mcp = {
    "coder" = {
      "command" = "coder"
      "args"    = ["exp", "mcp", "server"]
      "env" = {
        "CODER_MCP_APP_STATUS_SLUG" = var.report_tasks == true ? local.app_slug : ""
        "CODER_MCP_AI_AGENTAPI_URL" = var.report_tasks == true ? "http://localhost:3284" : ""
        "CODER_AGENT_TOKEN"         = data.external.env.result.CODER_AGENT_TOKEN
        "CODER_AGENT_URL"           = data.external.env.result.CODER_AGENT_URL
      }
      "type" = "stdio"
    }
  }

  additional_mcp = var.mcp != null ? jsondecode(var.mcp) : {}

  merged_mcp_servers = merge(
    lookup(local.user_config, "amp.mcpServers", {}),
    local.coder_mcp,
    local.additional_mcp
  )

  final_config = merge(local.base_amp_settings, {
    "amp.mcpServers" = local.merged_mcp_servers
  })

  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".amp-module"
  workdir         = trimsuffix(var.workdir, "/")
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "2.2.0"

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
  agentapi_version     = var.agentapi_version
  agentapi_cache_dir   = var.agentapi_cache_dir
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = <<-EOT
     #!/bin/bash
     set -o errexit
     set -o pipefail

     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
     chmod +x /tmp/start.sh
     ARG_AMP_API_KEY='${var.amp_api_key}' \
     ARG_AMP_START_DIRECTORY='${var.workdir}' \
     ARG_AMP_TASK_PROMPT='${base64encode(var.ai_prompt)}' \
     ARG_REPORT_TASKS='${var.report_tasks}' \
     ARG_MODE='${var.mode}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL_AMP='${var.install_amp}' \
    ARG_INSTALL_VIA_NPM='${var.install_via_npm}' \
    ARG_AMP_CONFIG="${base64encode(jsonencode(local.final_config))}" \
    ARG_AMP_VERSION='${var.amp_version}' \
    ARG_AMP_INSTRUCTION_PROMPT='${base64encode(var.instruction_prompt)}' \
    /tmp/install.sh
  EOT
}

output "task_app_id" {
  value = module.agentapi.task_app_id
}
