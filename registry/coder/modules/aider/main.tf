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

variable "workdir" {
  type        = string
  description = "The folder to run Aider in."
  default     = "/home/coder"
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
  description = "Whether to create a CLI app for Aider"
  default     = false
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Aider"
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app"
  default     = "Aider CLI"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Aider."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Aider."
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
  default     = "v0.6.3"
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for Claude Code."
  default     = ""
}

# ---------------------------------------------

variable "install_aider" {
  type        = bool
  description = "Whether to install Aider."
  default     = true
}

variable "system_prompt" {
  type        = string
  description = "System prompt for instructing Aider on task reporting and behavior"
  default     = "You are a helpful coding assistant that helps developers write, debug, and understand code. Provide clear explanations, follow best practices, and help solve coding problems efficiently."
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
    error_message = "provider must be one of: openai, anthropic, azure, google, cohere, mistral, ollama, custom"
  }
}

variable "model" {
  type        = string
  description = "AI model to use with Aider. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
}

variable "credentials" {
  type        = string
  description = "API key for the selected AI provider. This will be set as the appropriate environment variable based on the provider."
  default     = ""
  sensitive   = true
}

variable "custom_env_var_name" {
  type        = string
  description = "Custom environment variable name when using custom provider"
  default     = ""
}

variable "base_aider_config" {
  type        = string
  description = <<-EOT
    Base Aider configuration in yaml format. Will be stored in .aider.conf.yml file.
    
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
  app_slug              = "aider"
  base_aider_config     = var.base_aider_config != null ? "${replace(trimspace(var.base_aider_config), "\n", "\n  ")}" : ""
  task_reporting_prompt = <<-EOT

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
  EOT
  
  final_system_prompt   = var.report_tasks ? "<system>\n${var.system_prompt}${local.task_reporting_prompt}\n</system>" : "<system>\n${var.system_prompt}\n</system>"

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
  version = "1.2.0"

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
    ARG_WORKDIR='${var.workdir}' \
    ARG_API_KEY='${base64encode(var.credentials)}' \
    ARG_MODEL='${var.model}' \
    ARG_PROVIDER='${var.ai_provider}' \
    ARG_ENV_API_NAME_HOLDER='${local.env_var_name}' \
    ARG_SYSTEM_PROMPT='${base64encode(local.final_system_prompt)}' \
    ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
    /tmp/start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_WORKDIR='${var.workdir}' \
    ARG_MCP_APP_STATUS_SLUG='${local.app_slug}' \
    ARG_INSTALL_AIDER='${var.install_aider}' \
    ARG_SYSTEM_PROMPT='${base64encode(local.final_system_prompt)}' \
    ARG_REPORT_TASKS='${var.report_tasks}' \
    ARG_AIDER_CONFIG="$(echo -n '${base64encode(local.base_aider_config)}' | base64 -d)" \
    /tmp/install.sh
  EOT
}

