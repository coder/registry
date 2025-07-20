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

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key for Codex access."
  sensitive   = true
  default     = ""
}

variable "openai_model" {
  type        = string
  description = "OpenAI model to use for code generation."
  default     = "gpt-4"
}

variable "temperature" {
  type        = number
  description = "Temperature setting for code generation (0.0 to 2.0)."
  default     = 0.2

  validation {
    condition     = var.temperature >= 0.0 && var.temperature <= 2.0
    error_message = "Temperature must be between 0.0 and 2.0."
  }
}

variable "max_tokens" {
  type        = number
  description = "Maximum number of tokens for code generation."
  default     = 2048

  validation {
    condition     = var.max_tokens > 0 && var.max_tokens <= 4096
    error_message = "Max tokens must be between 1 and 4096."
  }
}

variable "folder" {
  type        = string
  description = "The folder to run Codex in."
  default     = "/home/coder"
}

variable "install_codex" {
  type        = bool
  description = "Whether to install Codex CLI."
  default     = true
}

variable "codex_version" {
  type        = string
  description = "Version of Codex CLI to install."
  default     = "latest"
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

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = "AI Tools"
}

variable "ai_prompt" {
  type        = string
  description = "Initial AI prompt for task reporting."
  default     = ""
}

locals {
  app_slug        = "codex"
  module_dir_name = "codex"
  icon_url        = "../../../../.icons/claude.svg"

  # Configuration for Codex CLI
  codex_config = {
    openai_model   = var.openai_model
    temperature    = var.temperature
    max_tokens     = var.max_tokens
    openai_api_key = var.openai_api_key
  }

  # Install script for Rust-based Codex CLI
  install_script = templatefile("${path.module}/scripts/install.sh", {
    CODEX_VERSION = var.codex_version
    INSTALL_CODEX = var.install_codex
  })

  # Start script for AgentAPI integration
  start_script = templatefile("${path.module}/scripts/start.sh", {
    OPENAI_API_KEY = var.openai_api_key
    OPENAI_MODEL   = var.openai_model
    TEMPERATURE    = var.temperature
    MAX_TOKENS     = var.max_tokens
    FOLDER         = var.folder
    AI_PROMPT      = var.ai_prompt
    RED            = "\\033[31m"
    GREEN          = "\\033[32m"
    YELLOW         = "\\033[33m"
    BOLD           = "\\033[1m"
    NC             = "\\033[0m"
  })
}

# Use the AgentAPI module for web chat UI and task reporting
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = local.icon_url
  web_app_display_name = "Codex CLI"
  cli_app_slug         = "codex-cli"
  cli_app_display_name = "Codex CLI"
  cli_app              = true
  cli_app_icon         = local.icon_url
  cli_app_order        = var.order
  cli_app_group        = var.group
  module_dir_name      = local.module_dir_name
  folder               = var.folder
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = local.install_script
}

# Create a workspace app for direct CLI access
resource "coder_app" "codex_terminal" {
  agent_id     = var.agent_id
  slug         = "codex-terminal"
  display_name = "Codex Terminal"
  icon         = local.icon_url
  order        = var.order
  group        = var.group
  command      = <<-EOT
    #!/bin/bash
    set -e
    
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    # Set up environment variables
    export OPENAI_API_KEY="${var.openai_api_key}"
    export OPENAI_MODEL="${var.openai_model}"
    export CODEX_TEMPERATURE="${var.temperature}"
    export CODEX_MAX_TOKENS="${var.max_tokens}"
    
    # Change to the workspace directory
    cd "${var.folder}"
    
    # Start interactive Codex CLI session
    codex-cli interactive
  EOT
}
