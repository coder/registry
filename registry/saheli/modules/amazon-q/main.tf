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

variable "amazon_q_version" {
  type        = string
  description = "The version of Amazon Q to install."
  default     = "latest"
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "latest"
}

variable "use_aider" {
  type        = bool
  description = "Whether to use Aider instead of Amazon Q CLI."
  default     = false
}

variable "aider_version" {
  type        = string
  description = "The version of Aider to install when use_aider is true."
  default     = "latest"
}

variable "experiment_use_screen" {
  type        = bool
  description = "Whether to use screen for running Amazon Q in the background."
  default     = false
}

variable "experiment_use_tmux" {
  type        = bool
  description = "Whether to use tmux instead of screen for running Amazon Q in the background."
  default     = false
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = true
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Amazon Q."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Amazon Q."
  default     = null
}

variable "aws_access_key_id" {
  type        = string
  description = "AWS Access Key ID for Amazon Q authentication"
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS Secret Access Key for Amazon Q authentication"
  sensitive   = true
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "AWS region for Amazon Q"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS profile to use for authentication"
  default     = "default"
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

variable "task_prompt" {
  type        = string
  description = "The initial task prompt to send to Amazon Q."
  default     = ""
}

variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

locals {
  app_slug        = "amazon-q"
  module_dir_name = ".amazon-q-module"

  # MCP extensions configuration following Goose pattern
  base_extensions = <<-EOT
coder:
  args:
  - exp
  - mcp
  - server
  cmd: coder
  description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
  enabled: true
  envs:
    CODER_MCP_APP_STATUS_SLUG: ${local.app_slug}
    CODER_MCP_AI_AGENTAPI_URL: http://localhost:3284
  name: Coder
  timeout: 3000
  type: stdio
developer:
  display_name: Developer
  enabled: true
  name: developer
  timeout: 300
  type: builtin
EOT

  # Format extensions to match YAML structure
  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.additional_extensions != null ? "\n  ${replace(trimspace(var.additional_extensions), "\n", "\n  ")}" : ""
  combined_extensions   = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT

  # Load scripts from files like Goose module
  install_script_content = file("${path.module}/scripts/install.sh")
  start_script_content   = file("${path.module}/scripts/start.sh")

}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = var.use_aider ? "Amazon Q + Aider" : "Amazon Q"
  cli_app              = true
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = var.use_aider ? "Amazon Q + Aider CLI" : "Amazon Q CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.experiment_pre_install_script
  post_install_script  = var.experiment_post_install_script
  start_script         = local.start_script_content
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script_content)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_AMAZON_Q_CONFIG="$(echo -n '${base64encode(local.combined_extensions)}' | base64 -d)" \
    ARG_INSTALL='${var.install_amazon_q}' \
    ARG_AMAZON_Q_VERSION='${var.amazon_q_version}' \
    ARG_USE_AIDER='${var.use_aider}' \
    ARG_AIDER_VERSION='${var.aider_version}' \
    ARG_AWS_ACCESS_KEY_ID='${var.aws_access_key_id}' \
    ARG_AWS_SECRET_ACCESS_KEY='${var.aws_secret_access_key}' \
    ARG_AWS_REGION='${var.aws_region}' \
    ARG_AWS_PROFILE='${var.aws_profile}' \
    /tmp/install.sh
  EOT

}

# Create web app for Amazon Q chat interface
resource "coder_app" "amazon_q_web" {
  count = var.experiment_report_tasks ? 1 : 0

  slug         = "aqw" # Short slug to avoid URL length issues
  display_name = var.use_aider ? "Amazon Q + Aider Web" : "Amazon Q Web"
  agent_id     = var.agent_id
  url          = "http://localhost:3284/"
  subdomain    = true
  healthcheck {
    url       = "http://localhost:3284/status"
    interval  = 3
    threshold = 20
  }
}

# Create AI task resource for sidebar integration
resource "coder_ai_task" "amazon_q" {
  count = var.experiment_report_tasks ? 1 : 0

  sidebar_app {
    id = coder_app.amazon_q_web[0].id
  }
}
