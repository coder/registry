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
  description = "Whether to install the Pi coding agent CLI."
  default     = true
}

variable "pi_version" {
  type        = string
  description = "The npm version of @earendil-works/pi-coding-agent to install. Use 'latest' for the latest version or a specific version like '0.12.0'."
  default     = "latest"
}

variable "anthropic_api_key" {
  type        = string
  description = "API key passed to Pi via the ANTHROPIC_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  type        = string
  description = "API key passed to Pi via the OPENAI_API_KEY env var."
  sensitive   = true
  default     = ""
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

resource "coder_env" "extra_env" {
  for_each = nonsensitive(toset(keys(var.extra_env)))
  agent_id = var.agent_id
  name     = each.value
  value    = var.extra_env[each.value]
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_PI            = tostring(var.install_pi)
    ARG_PI_VERSION            = var.pi_version
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_DEFAULT_PROJECT_TRUST = var.default_project_trust
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
