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

# ---------------------------------------------

variable "install_aider" {
  type        = bool
  description = "Whether to install Aider."
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
  description = "AI model to use with Aider. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
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

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_AIDER = tostring(var.install_aider)
    ARG_AIDER_CONFIG  = local.base_aider_config
    ARG_WORKDIR       = var.workdir
  })
  module_dir_name = ".coder-modules/coder/aider"
}

resource "coder_env" "aider_api_key" {
  count    = var.api_key != "" ? 1 : 0
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
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}