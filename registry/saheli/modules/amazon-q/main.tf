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
  app_slug = "amazon-q"
  module_dir_name = ".amazon-q-module"
  
  # Load scripts from files like Goose module
  install_script_content = file("${path.module}/scripts/install.sh")
  start_script_content = templatefile("${path.module}/scripts/start.sh", {
    system_prompt = var.system_prompt
    task_prompt = var.task_prompt
    folder = var.folder
    use_aider = var.use_aider
    report_tasks = var.experiment_report_tasks
    aws_access_key_id = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    aws_region = var.aws_region
    aws_profile = var.aws_profile
  })
  
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
  install_script       = local.install_script_content
  
}
