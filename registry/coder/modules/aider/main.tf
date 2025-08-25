terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
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
  default     = "/icon/aider.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Aider in."
  default     = "/home/coder"
}

variable "install_aider" {
  type        = bool
  description = "Whether to install Aider."
  default     = true
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = true
}

variable "system_prompt" {
  type        = string
  description = "System prompt for instructing Aider on task reporting and behavior"
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
    - Include clear and actionable steps for the user.
    - Be less than 160 characters in length.
  EOT
}

variable "task_prompt" {
  type        = string
  description = "Task prompt to use with Aider"
  default     = ""
}

variable "aider_prompt" {
  type        = bool
  description = "This prompt will be sent to Aider and should run only once, and AgentAPI will be disabled."
  default     = false
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Aider."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Aider."
  default     = null
}

variable "experiment_additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

variable "ai_provider" {
  type        = string
  description = "AI provider to use with Aider (openai, anthropic, azure, google, etc.)"
  default     = "google"
  validation {
    condition     = contains(["openai", "anthropic", "azure", "google", "cohere", "mistral", "ollama", "custom"], var.ai_provider)
    error_message = "ai_provider must be one of: openai, anthropic, azure, google, cohere, mistral, ollama, custom"
  }
}

variable "ai_model" {
  type        = string
  description = "AI model to use with Aider. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
  default     = "gemini"
}

variable "ai_api_key" {
  type        = string
  description = "API key for the selected AI provider. This will be set as the appropriate environment variable based on the provider."
  default     = ""
  sensitive   = true
}

resource "coder_env" "ai_api_key" {
  agent_id = var.agent_id
  name     = "ARG_API_KEY"
  value    = var.ai_api_key
}

variable "custom_env_var_name" {
  type        = string
  description = "Custom environment variable name when using custom provider"
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
  default     = "v0.3.0"
}

variable "base_aider_config" {
  type        = string
  description = <<-EOT
    Base Aider configuration in ynl format. Will be Store in .aider.conf.yml file.
    
    options include:
    read:
      - CONVENTIONS.md
      - anotherfile.txt
      - thirdfile.py
    model: xxx
    ##Specify the OpenAI API key
    openai-api-key: xxx
    ## (deprecated, use --set-env OPENAI_API_TYPE=<value>)
    openai-api-type: xxx
    ## (deprecated, use --set-env OPENAI_API_VERSION=<value>)
    openai-api-version: xxx
    ## (deprecated, use --set-env OPENAI_API_DEPLOYMENT_ID=<value>)
    openai-api-deployment-id: xxx
    ## Set an environment variable (to control API settings, can be used multiple times)
    set-env: xxx
    ## Specify multiple values like this:
    set-env:
      - xxx
      - yyy
      - zzz

    Reference : https://aider.chat/docs/config/aider_conf.html
  EOT
  default     = null
}


locals {
  app_slug  = "aider"
  coder_mcp = <<-EOT
  coder:
    args:
    - exp
    - mcp
    - server
    cmd: coder
    description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
    enabled: true
    envs:
      -  CODER_MCP_APP_STATUS_SLUG: aider
      -  CODER_MCP_AI_AGENTAPI_URL: "http://localhost:3284"
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

  formatted_base        = "\n  ${replace(trimspace(local.coder_mcp), "\n", "\n  ")}"
  additional_extensions = var.experiment_additional_extensions != null ? "\n  ${replace(trimspace(var.experiment_additional_extensions), "\n", "\n  ")}" : ""
  base_aider_config     = var.base_aider_config != null ? "${replace(trimspace(var.base_aider_config), "\n", "\n  ")}" : ""
  combined_extensions   = <<-EOT
    extensions:
      ${local.base_aider_config}${local.formatted_base}${local.additional_extensions}
  EOT

  # Map providers to their environment variable names
  provider_env_vars = {
    openai    = "OPENAI_API_KEY"
    anthropic = "ANTHROPIC_API_KEY"
    azure     = "AZURE_OPENAI_API_KEY"
    google    = "GEMINI_API_KEY"
    cohere    = "COHERE_API_KEY"
    mistral   = "MISTRAL_API_KEY"
    ollama    = "OLLAMA_HOST"
    custom    = var.custom_env_var_name
  }

  # Get the environment variable name for selected provider
  env_var_name = local.provider_env_vars[var.ai_provider]

  # Model flag for aider command
  model_flag = var.ai_provider == "ollama" ? "--ollama-model" : "--model"

  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".aider-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Aider"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Aider CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.experiment_pre_install_script
  post_install_script  = var.experiment_post_install_script
  start_script         = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
    chmod +x /tmp/start.sh   
    AIDER_START_DIRECTORY='${var.folder}' \
    ARG_API_KEY='${var.ai_api_key}' \
    ARG_AI_MODULE='${var.ai_model}' \
    ARG_AI_PROVIDER='${var.ai_provider}' \
    ARG_ENV_API_NAME_HOLDER='${local.env_var_name}' \
    ARG_TASK_PROMPT='${base64encode(var.task_prompt)}' \
    AIDER_PROMPT='${var.aider_prompt}' \
    /tmp/start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    AIDER_START_DIRECTORY='${var.folder}' \
    ARG_INSTALL_AIDER='${var.install_aider}' \
    AIDER_SYSTEM_PROMPT='${var.system_prompt}' \
    ARG_IMPLEMENT_MCP='${var.experiment_report_tasks}' \
    ARG_AIDER_CONFIG="$(echo -n '${base64encode(trimspace(local.combined_extensions))}' | base64 -d)" \
    /tmp/install.sh
  EOT
}

