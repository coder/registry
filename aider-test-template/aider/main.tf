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

variable "aider_version" {
  type        = string
  description = "The version of Aider to install."
  default     = "latest"
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "latest"
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
  default     = "anthropic"
  validation {
    condition     = contains(["openai", "anthropic", "azure", "google", "cohere", "mistral", "ollama", "custom"], var.ai_provider)
    error_message = "ai_provider must be one of: openai, anthropic, azure, google, cohere, mistral, ollama, custom"
  }
}

variable "ai_model" {
  type        = string
  description = "AI model to use with Aider. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
  default     = "sonnet"
}

variable "ai_api_key" {
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

locals {
  app_slug = "aider"
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

  # Add two spaces to each line of extensions to match YAML structure
  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.experiment_additional_extensions != null ? "\n  ${replace(trimspace(var.experiment_additional_extensions), "\n", "\n  ")}" : ""
  combined_extensions   = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT
  install_script = file("${path.module}/scripts/install.sh")
  start_script   = file("${path.module}/scripts/start.sh")
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
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.experiment_pre_install_script
  post_install_script  = var.experiment_post_install_script
  start_script         = local.start_script
  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_PROVIDER='${var.ai_provider}' \
    ARG_MODEL='${var.ai_model}' \
    ARG_AIDER_CONFIG="$(echo -n '${base64encode(local.combined_extensions)}' | base64 -d)" \
    ARG_INSTALL='${var.install_aider}' \
    ARG_AIDER_VERSION='${var.aider_version}' \
    /tmp/install.sh
  EOT
}