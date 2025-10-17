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

variable "web_app_order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "web_app_group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "web_app_icon" {
  type        = string
  description = "The icon to use for the app."
}

variable "web_app_display_name" {
  type        = string
  description = "The display name of the web app."
}

variable "web_app_slug" {
  type        = string
  description = "The slug of the web app."
}

variable "folder" {
  type        = string
  description = "The folder to run AgentAPI in."
  default     = "/home/coder"
}

variable "cli_app" {
  type        = bool
  description = "Whether to create the CLI workspace app."
  default     = false
}

variable "cli_app_order" {
  type        = number
  description = "The order of the CLI workspace app."
  default     = null
}

variable "cli_app_group" {
  type        = string
  description = "The group of the CLI workspace app."
  default     = null
}

variable "cli_app_icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/claude.svg"
}

variable "cli_app_display_name" {
  type        = string
  description = "The display name of the CLI workspace app."
}

variable "cli_app_slug" {
  type        = string
  description = "The slug of the CLI workspace app."
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing the agent used by AgentAPI."
  default     = null
}

variable "install_script" {
  type        = string
  description = "Script to install the agent used by AgentAPI."
  default     = ""
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing the agent used by AgentAPI."
  default     = null
}

variable "start_script" {
  type        = string
  description = "Script that starts AgentAPI."
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.10.0"
}

variable "agentapi_port" {
  type        = number
  description = "The port used by AgentAPI."
  default     = 3284
}

locals {
  # agentapi_subdomain_false_min_version_expr matches a semantic version >= v0.3.3.
  # Initial support was added in v0.3.1 but configuration via environment variable
  # was added in v0.3.3.
  # This is unfortunately a regex because there is no builtin way to compare semantic versions in Terraform.
  # See: https://regex101.com/r/oHPyRa/1
  agentapi_subdomain_false_min_version_expr = "^v(0\\.(3\\.[3-9]|3.[1-9]\\d+|[4-9]\\.\\d+|[1-9]\\d+\\.\\d+)|[1-9]\\d*\\.\\d+\\.\\d+)$"
}

variable "agentapi_subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = true
  validation {
    condition = var.agentapi_subdomain || (
      # If version doesn't look like a valid semantic version, just allow it.
      # Note that boolean operators do not short-circuit in Terraform.
      can(regex("^v\\d+\\.\\d+\\.\\d+$", var.agentapi_version)) ?
      can(regex(local.agentapi_subdomain_false_min_version_expr, var.agentapi_version)) :
      true
    )
    error_message = "Running with subdomain = false is only supported by agentapi >= v0.3.3."
  }
}

variable "module_dir_name" {
  type        = string
  description = "Name of the subdirectory in the home directory for module files."
}

variable "enable_tasks" {
  type        = bool
  description = "Whether to enable AI tasks. When false, the coder_ai_task resource will not be created, avoiding the requirement for an 'AI Prompt' parameter."
  default     = true
}

locals {
  # we always trim the slash for consistency
  workdir                            = trimsuffix(var.folder, "/")
  encoded_pre_install_script         = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_install_script             = var.install_script != null ? base64encode(var.install_script) : ""
  encoded_post_install_script        = var.post_install_script != null ? base64encode(var.post_install_script) : ""
  agentapi_start_script_b64          = base64encode(var.start_script)
  agentapi_wait_for_start_script_b64 = base64encode(file("${path.module}/scripts/agentapi-wait-for-start.sh"))
  // Chat base path is only set if not using a subdomain.
  // NOTE:
  //   - Initial support for --chat-base-path was added in v0.3.1 but configuration
  //     via environment variable AGENTAPI_CHAT_BASE_PATH was added in v0.3.3.
  //   - As CODER_WORKSPACE_AGENT_NAME is a recent addition we use agent ID
  //     for backward compatibility.
  agentapi_chat_base_path = var.agentapi_subdomain ? "" : "/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.${var.agent_id}/apps/${var.web_app_slug}/chat"
  main_script             = file("${path.module}/scripts/main.sh")
}

resource "coder_script" "agentapi" {
  agent_id     = var.agent_id
  display_name = "Install and start AgentAPI"
  icon         = var.web_app_icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.main_script)}' | base64 -d > /tmp/main.sh
    chmod +x /tmp/main.sh

    ARG_MODULE_DIR_NAME='${var.module_dir_name}' \
    ARG_WORKDIR="$(echo -n '${base64encode(local.workdir)}' | base64 -d)" \
    ARG_PRE_INSTALL_SCRIPT="$(echo -n '${local.encoded_pre_install_script}' | base64 -d)" \
    ARG_INSTALL_SCRIPT="$(echo -n '${local.encoded_install_script}' | base64 -d)" \
    ARG_INSTALL_AGENTAPI='${var.install_agentapi}' \
    ARG_AGENTAPI_VERSION='${var.agentapi_version}' \
    ARG_START_SCRIPT="$(echo -n '${local.agentapi_start_script_b64}' | base64 -d)" \
    ARG_WAIT_FOR_START_SCRIPT="$(echo -n '${local.agentapi_wait_for_start_script_b64}' | base64 -d)" \
    ARG_POST_INSTALL_SCRIPT="$(echo -n '${local.encoded_post_install_script}' | base64 -d)" \
    ARG_AGENTAPI_PORT='${var.agentapi_port}' \
    ARG_AGENTAPI_CHAT_BASE_PATH='${local.agentapi_chat_base_path}' \
    /tmp/main.sh
    EOT
  run_on_start = true
}

resource "coder_app" "agentapi_web" {
  slug         = var.web_app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = "http://localhost:${var.agentapi_port}/"
  icon         = var.web_app_icon
  order        = var.web_app_order
  group        = var.web_app_group
  subdomain    = var.agentapi_subdomain
  healthcheck {
    url       = "http://localhost:${var.agentapi_port}/status"
    interval  = 3
    threshold = 20
  }
}

resource "coder_app" "agentapi_cli" {
  count = var.cli_app ? 1 : 0

  slug         = var.cli_app_slug
  display_name = var.cli_app_display_name
  agent_id     = var.agent_id
  command      = <<-EOT
    #!/bin/bash
    set -e

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    agentapi attach
    EOT
  icon         = var.cli_app_icon
  order        = var.cli_app_order
  group        = var.cli_app_group
}

resource "coder_ai_task" "agentapi" {
  count = var.enable_tasks ? 1 : 0

  sidebar_app {
    id = coder_app.agentapi_web.id
  }
}