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
  default     = "/icon/auggie.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Auggie in."
}

variable "install_auggie" {
  type        = bool
  description = "Whether to install Auggie CLI."
  default     = true
}

variable "auggie_version" {
  type        = string
  description = "The version of Auggie to install."
  default     = "" # empty string means the latest available version
  validation {
    condition     = var.auggie_version == "" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+", var.auggie_version))
    error_message = "auggie_version must be empty (for latest) or a valid semantic version like 'v1.2.3' or '1.2.3'."
  }
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.6.0"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.agentapi_version))
    error_message = "agentapi_version must be a valid semantic version starting with 'v', like 'v0.3.3'."
  }
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Auggie."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Auggie."
  default     = null
}

# ----------------------------------------------

variable "ai_prompt" {
  type        = string
  description = "Task prompt for the Auggie CLI"
  default     = ""
}

variable "mcp" {
  type        = string
  description = "MCP configuration as a JSON string for the auggie cli, check https://docs.augmentcode.com/cli/integrations#mcp-integrations"
  default     = ""
}

variable "mcp_files" {
  type        = list(string)
  description = "MCP configuration from a JSON file for the auggie cli, check https://docs.augmentcode.com/cli/integrations#mcp-integrations"
  default     = []
}

variable "rules" {
  type        = string
  description = "Additional rules to append to workspace guidelines (markdown format)"
  default     = ""
}

variable "continue_previous_conversation" {
  type        = bool
  description = "Whether to resume the previous conversation."
  default     = false
}

variable "interaction_mode" {
  type        = string
  description = "Interaction mode with the Auggie CLI. Options: interactive, print, quiet, compact. https://docs.augmentcode.com/cli/reference#cli-flags"
  default     = "interactive"
  validation {
    condition     = contains(["interactive", "print", "quiet", "compact"], var.interaction_mode)
    error_message = "interaction_mode must be one of: interactive, print, quiet, compact."
  }
}

variable "augment_session_token" {
  type        = string
  description = "Auggie session token for authentication. https://docs.augmentcode.com/cli/setup-auggie/authentication"
  default     = ""
}

variable "auggie_model" {
  type        = string
  description = "The model to use for Auggie, find available models using auggie --list-models"
  default     = ""
}

variable "report_tasks" {
  type        = bool
  description = "Whether to enable task reporting to Coder UI via AgentAPI"
  default     = false
}

variable "cli_app" {
  type        = bool
  description = "Whether to create a CLI app for Auggie"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Auggie"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "Auggie CLI"
}

resource "coder_env" "auggie_session_auth" {
  agent_id = var.agent_id
  name     = "AUGMENT_SESSION_AUTH"
  value    = var.augment_session_token
}

locals {
  app_slug        = "auggie"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".auggie-module"
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
     ARG_AUGGIE_START_DIRECTORY='${var.folder}' \
     ARG_TASK_PROMPT='${base64encode(var.ai_prompt)}' \
     ARG_MCP_FILES='${jsonencode(var.mcp_files)}' \
     ARG_AUGGIE_RULES='${base64encode(var.rules)}' \
     ARG_AUGGIE_CONTINUE_PREVIOUS_CONVERSATION='${var.continue_previous_conversation}' \
     ARG_AUGGIE_INTERACTION_MODE='${var.interaction_mode}' \
     ARG_AUGMENT_SESSION_AUTH='${var.augment_session_token}' \
     ARG_AUGGIE_MODEL='${var.auggie_model}' \
     ARG_REPORT_TASKS='${var.report_tasks}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_AUGGIE_INSTALL='${var.install_auggie}' \
    ARG_AUGGIE_VERSION='${var.auggie_version}' \
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_AUGGIE_RULES='${base64encode(var.rules)}' \
    ARG_MCP_CONFIG='${var.mcp != null ? base64encode(replace(var.mcp, "'", "'\\''")) : ""}' \
    /tmp/install.sh
  EOT
}