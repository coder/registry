terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "icon" {
  description = "The icon to use for the app."
  type        = string
  default     = "/icon/poolside.svg"
}

variable "pre_install_script" {
  description = "Custom script to run before installing Pool CLI."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Pool CLI."
  type        = string
  default     = null
}

variable "install_pool" {
  description = "Whether to install Pool CLI. Set false when Pool is already installed in the workspace image."
  type        = bool
  default     = true
}

variable "pool_binary_path" {
  description = "Directory containing the Pool CLI binary. The installer uses this directory when install_pool is true."
  type        = string
  default     = "$HOME/.local/bin"
}

variable "poolside_api_key" {
  description = "Poolside API key passed to Pool CLI via POOLSIDE_API_KEY."
  type        = string
  default     = ""
  sensitive   = true
}

variable "poolside_api_url" {
  description = "Optional Poolside deployment API URL passed to Pool CLI via POOLSIDE_API_URL."
  type        = string
  default     = ""
}

variable "standalone_base_url" {
  description = "Optional OpenAI-compatible API base URL passed to Pool CLI via POOLSIDE_STANDALONE_BASE_URL. Use this for a non-Coder gateway or local inference server."
  type        = string
  default     = ""

  validation {
    condition     = !(var.enable_ai_gateway && var.standalone_base_url != "")
    error_message = "standalone_base_url cannot be provided when enable_ai_gateway is true."
  }
}

variable "model" {
  description = "Optional model passed to Pool CLI via POOLSIDE_STANDALONE_MODEL when using an OpenAI-compatible API or Coder AI Gateway."
  type        = string
  default     = ""
}

variable "enable_ai_gateway" {
  description = "Use Coder AI Gateway through its OpenAI-compatible endpoint. https://coder.com/docs/ai-coder/ai-gateway"
  type        = bool
  default     = false

  validation {
    condition     = !(var.enable_ai_gateway && var.poolside_api_key != "")
    error_message = "poolside_api_key cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates Pool CLI using Coder credentials."
  }
}

resource "coder_env" "poolside_api_key" {
  count    = var.poolside_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_API_KEY"
  value    = var.poolside_api_key
}

resource "coder_env" "poolside_api_url" {
  count    = var.poolside_api_url != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_API_URL"
  value    = var.poolside_api_url
}

resource "coder_env" "standalone_base_url" {
  count    = var.standalone_base_url != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_STANDALONE_BASE_URL"
  value    = var.standalone_base_url
}

resource "coder_env" "model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_STANDALONE_MODEL"
  value    = var.model
}

# Pool CLI uses POOLSIDE_API_KEY for OpenAI-compatible API authentication.
# Coder AI Gateway accepts the workspace owner's session token as a bearer token.
resource "coder_env" "ai_gateway_session_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_API_KEY"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "ai_gateway_base_url" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "POOLSIDE_STANDALONE_BASE_URL"
  value    = "${trimsuffix(data.coder_workspace.me.access_url, "/")}/api/v2/ai-gateway/openai/v1"
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_POOL     = tostring(var.install_pool)
    ARG_POOL_BINARY_PATH = var.pool_binary_path
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder-labs/pool"
  display_name_prefix = "Pool CLI"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
