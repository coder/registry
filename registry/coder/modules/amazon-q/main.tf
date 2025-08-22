# Improved amazon-q module main.tf

terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7" # Updated to match cursor-cli
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
  default     = "/icon/amazon-q.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Amazon Q in."
  default     = "/home/coder"
}

variable "install_amazon_q" {
  type        = bool
  description = "Whether to install Amazon Q."
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

variable "amazon_q_version" {
  type        = string
  description = "The version of Amazon Q to install."
  default     = "latest"
}

variable "trust_all_tools" {
  type        = bool
  description = "Whether to trust all tools in Amazon Q."
  default     = true
}

variable "ai_prompt" {
  type        = string
  description = "The initial task prompt to send to Amazon Q."
  default     = ""
}

variable "system_prompt" {
  type        = string
  description = "The system prompt to use for Amazon Q. This should instruct the agent how to do task reporting."
  default     = <<-EOT
    You are a helpful Coding assistant. Aim to autonomously investigate
    and solve issues the user gives you and test your work, whenever possible.
    Avoid shortcuts like mocking tests. When you get stuck, you can ask the user
    but opt for autonomy.

    YOU MUST REPORT ALL TASKS TO CODER.
    When reporting tasks, you MUST follow these EXACT instructions:
    - IMMEDIATELY report status after receiving ANY user message.
    - Be granular. If you are investigating with multiple steps, report each step to coder.

    Task state MUST be one of the following:
    - Use "state": "working" when actively processing WITHOUT needing additional user input.
    - Use "state": "complete" only when finished with a task.
    - Use "state": "failure" when you need ANY user input, lack sufficient details, or encounter blockers.

    Task summaries MUST:
    - Include specifics about what you're doing.
    - Include clear and actionable steps for the user.
    - Be less than 160 characters in length.
  EOT
}

variable "auth_tarball" {
  type        = string
  description = "Base64 encoded, zstd compressed tarball of a pre-authenticated ~/.local/share/amazon-q directory. After running `q login` on another machine, you may generate it with: `cd ~/.local/share/amazon-q && tar -c . | zstd | base64 -w 0`"
  default     = ""
  sensitive   = true
}

variable "pre_install_script" {
  type        = string
  description = "Optional script to run before installing Amazon Q."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Optional script to run after installing Amazon Q."
  default     = null
}

variable "agent_config" {
  type        = string
  description = "Optional Agent configuration JSON for Amazon Q."
  default     = null
}

# Expose status slug to the agent environment
resource "coder_env" "status_slug" {
  agent_id = var.agent_id
  name     = "CODER_MCP_APP_STATUS_SLUG"
  value    = local.app_slug
}

# Expose auth tarball as environment variable for install script
resource "coder_env" "auth_tarball" {
  count    = var.auth_tarball != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "AMAZON_Q_AUTH_TARBALL"
  value    = var.auth_tarball
}

locals {
  app_slug        = "amazonq"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".amazonq"
  agent_config = var.agent_config == null ? templatefile("${path.module}/templates/agent-config.json.tpl", {
    system_prompt = var.system_prompt
  }) : var.agent_config
  full_prompt = var.ai_prompt != null ? "${var.ai_prompt}" : ""
}


module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Amazon Q"
  cli_app_slug         = local.app_slug
  cli_app_display_name = "Amazon Q"
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
    ARG_TRUST_ALL_TOOLS='${var.trust_all_tools}' \
    ARG_AI_PROMPT='${base64encode(local.full_prompt)}' \
    ARG_MODULE_DIR_NAME='${local.module_dir_name}' \
    ARG_FOLDER='${var.folder}' \
    SERVER_PARAMETERS="/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.${var.agent_id}/apps/${local.app_slug}/chat" \
    /tmp/start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_amazon_q}' \
    ARG_VERSION='${var.amazon_q_version}' \
    ARG_AUTH_TARBALL='${var.auth_tarball}' \
    ARG_AGENT_CONFIG='${local.agent_config != null ? base64encode(local.agent_config) : ""}' \
    ARG_MODULE_DIR_NAME='${local.module_dir_name}' \
    ARG_CODER_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_PRE_INSTALL_SCRIPT='${var.pre_install_script != null ? base64encode(var.pre_install_script) : ""}' \
    ARG_POST_INSTALL_SCRIPT='${var.post_install_script != null ? base64encode(var.post_install_script) : ""}' \
    /tmp/install.sh
  EOT
}
