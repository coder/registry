terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/pi.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Pi. Can be used for dependency ordering between modules (e.g., waiting for git-clone to complete before Pi initialization)."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Pi."
  default     = null
}

variable "install_pi" {
  type        = bool
  description = "Whether to install the Pi coding agent CLI. Set to false when Pi is already baked into the workspace image."
  default     = true
}

variable "pi_binary_path" {
  type        = string
  description = "Absolute path to an existing Pi executable. Only used when install_pi is false; leave empty to look up pi on PATH."
  default     = ""

  validation {
    condition     = var.pi_binary_path == "" || startswith(var.pi_binary_path, "/")
    error_message = "pi_binary_path must be an absolute path."
  }

  validation {
    condition     = !(var.install_pi && var.pi_binary_path != "")
    error_message = "pi_binary_path can only be set when install_pi is false."
  }
}

variable "npm_registry_url" {
  type        = string
  description = "npm registry URL to install @earendil-works/pi-coding-agent from. Override to install from an internal mirror or artifact store (for example Artifactory or Nexus). Leave empty to use npm's configured registry."
  default     = ""

  validation {
    condition     = var.npm_registry_url == "" || can(regex("^https?://", var.npm_registry_url))
    error_message = "npm_registry_url must be an http(s) URL when set."
  }
}

variable "pi_version" {
  type        = string
  description = "The npm version of @earendil-works/pi-coding-agent to install. Use 'latest' for the latest version or a specific version like '0.12.0'."
  default     = "latest"
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Route Pi's Anthropic and OpenAI providers through Coder AI Gateway, authenticated with the workspace owner's Coder session token. https://coder.com/docs/ai-coder/ai-gateway"
  default     = false
}

variable "anthropic_api_key" {
  type        = string
  description = "API key passed to Pi via the ANTHROPIC_API_KEY env var."
  sensitive   = true
  default     = ""

  validation {
    condition     = !(var.enable_ai_gateway && var.anthropic_api_key != "")
    error_message = "anthropic_api_key cannot be provided when enable_ai_gateway is true. AI Gateway authenticates Pi using Coder credentials."
  }
}

variable "openai_api_key" {
  type        = string
  description = "API key passed to Pi via the OPENAI_API_KEY env var."
  sensitive   = true
  default     = ""

  validation {
    condition     = !(var.enable_ai_gateway && var.openai_api_key != "")
    error_message = "openai_api_key cannot be provided when enable_ai_gateway is true. AI Gateway authenticates Pi using Coder credentials."
  }
}

variable "gemini_api_key" {
  type        = string
  description = "API key passed to Pi via the GEMINI_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "extra_env" {
  type        = map(string)
  description = "Additional environment variables to pass to Pi, e.g. for other supported providers (Azure OpenAI, Mistral, Groq, DeepSeek, etc). Keys are used as-is as env var names."
  default     = {}
  sensitive   = true
}

variable "default_project_trust" {
  type        = string
  description = "Written to defaultProjectTrust in ~/.pi/agent/settings.json, controlling whether Pi prompts to trust a project folder on first run. One of: ask, always, never."
  default     = "always"

  validation {
    condition     = contains(["ask", "always", "never"], var.default_project_trust)
    error_message = "default_project_trust must be one of: ask, always, never."
  }
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "openai_api_key" {
  count    = var.openai_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

resource "coder_env" "gemini_api_key" {
  count    = var.gemini_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GEMINI_API_KEY"
  value    = var.gemini_api_key
}

# Pi sends ANTHROPIC_API_KEY as X-Api-Key and OPENAI_API_KEY as a bearer
# token. AI Gateway accepts the Coder session token in either header.
resource "coder_env" "ai_gateway_anthropic_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "ai_gateway_openai_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "extra_env" {
  for_each = nonsensitive(toset(keys(var.extra_env)))
  agent_id = var.agent_id
  name     = each.value
  value    = var.extra_env[each.value]
}

locals {
  workdir             = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  ai_gateway_base_url = var.enable_ai_gateway ? "${trimsuffix(data.coder_workspace.me.access_url, "/")}/api/v2/ai-gateway" : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_PI            = tostring(var.install_pi)
    ARG_PI_VERSION            = var.pi_version
    ARG_PI_BINARY_PATH        = var.pi_binary_path != "" ? base64encode(var.pi_binary_path) : ""
    ARG_NPM_REGISTRY_URL      = var.npm_registry_url
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_DEFAULT_PROJECT_TRUST = var.default_project_trust
    ARG_AI_GATEWAY_BASE_URL   = local.ai_gateway_base_url
  })
  module_dir_name = ".coder-modules/coder-labs/pi"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Pi"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
