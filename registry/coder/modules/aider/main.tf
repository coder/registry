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

variable "icon" {
  type        = string
  description = "The icon to use for the install scripts."
  default     = "/icon/aider.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
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

variable "install_aider" {
  type        = bool
  description = "Whether to install Aider with the official installer (https://aider.chat/install.sh). When false, a working aider must already be on PATH."
  default     = true
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
  description = "AI model to use with Aider, exported as AIDER_MODEL. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
}

variable "api_key" {
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
  description = "Aider configuration in YAML format, written to ~/.aider.conf.yml. Use api_key for credentials instead of putting them here. See https://aider.chat/docs/config/aider_conf.html"
  default     = null
}

locals {
  provider_env_vars = {
    openai    = "OPENAI_API_KEY"
    anthropic = "ANTHROPIC_API_KEY"
    azure     = "AZURE_OPENAI_API_KEY"
    google    = "GEMINI_API_KEY"
    cohere    = "COHERE_API_KEY"
    mistral   = "MISTRAL_API_KEY"
    ollama    = "OLLAMA_API_KEY"
    custom    = var.custom_env_var_name
  }

  env_var_name = local.provider_env_vars[var.ai_provider]

  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL      = tostring(var.install_aider)
    ARG_WORKDIR      = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_AIDER_CONFIG = var.base_aider_config != null ? base64encode(trimspace(var.base_aider_config)) : ""
  })
  module_dir_name = ".coder-modules/coder/aider"
}

resource "coder_env" "aider_model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "AIDER_MODEL"
  value    = var.model
}

resource "coder_env" "api_key" {
  count    = var.api_key != "" && local.env_var_name != "" ? 1 : 0
  agent_id = var.agent_id
  name     = local.env_var_name
  value    = var.api_key
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Aider"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
