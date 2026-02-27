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
  default     = "/icon/opencode.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run OpenCode in."
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via AgentAPI"
  default     = true
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for OpenCode"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "OpenCode"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "OpenCode CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing OpenCode."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing OpenCode."
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
  default     = "v0.11.2"
}

variable "agentapi_cache_dir" {
  type        = string
  description = "Path to a directory where the AgentAPI binary will be cached after download. On subsequent workspace starts, the cached binary is used instead of downloading again."
  default     = ""
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for OpenCode."
  default     = ""
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}

variable "install_opencode" {
  type        = bool
  description = "Whether to install OpenCode."
  default     = true
}

variable "opencode_version" {
  type        = string
  description = "The version of OpenCode to install."
  default     = "latest"
}

variable "continue" {
  type        = bool
  description = "continue the last session. Uses the --continue flag"
  default     = false
}

variable "session_id" {
  type        = string
  description = "Session id to continue. Passed via --session"
  default     = ""
}

variable "auth_json" {
  type        = string
  description = "Your auth.json from $HOME/.local/share/opencode/auth.json, Required for non-interactive authentication"
  default     = ""
}

variable "config_json" {
  type        = string
  description = "OpenCode JSON config. https://opencode.ai/docs/config/"
  default     = ""
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "opencode"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".opencode-module"
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
  cli_app              = var.cli_app
  cli_app_slug         = var.cli_app ? "${local.app_slug}-cli" : null
  cli_app_display_name = var.cli_app ? var.cli_app_display_name : null
  agentapi_subdomain   = var.subdomain
  folder               = local.workdir
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

     ARG_WORKDIR='${local.workdir}' \
     ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
     ARG_SESSION_ID='${var.session_id}' \
     ARG_REPORT_TASKS='${var.report_tasks}' \
     ARG_CONTINUE='${var.continue}' \
     /tmp/start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_OPENCODE_VERSION='${var.opencode_version}' \
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_INSTALL_OPENCODE='${var.install_opencode}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_WORKDIR='${local.workdir}' \
    ARG_AUTH_JSON='${var.auth_json != null ? base64encode(replace(var.auth_json, "'", "'\\''")) : ""}' \
    ARG_OPENCODE_CONFIG='${var.config_json != null ? base64encode(replace(var.config_json, "'", "'\\''")) : ""}' \
    /tmp/install.sh
  EOT
}

output "task_app_id" {
  value = module.agentapi.task_app_id
}
