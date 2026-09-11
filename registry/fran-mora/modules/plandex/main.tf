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

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/plandex.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing so Plandex can be opened in it directly."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Plandex. Useful for dependency ordering between modules."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Plandex."
  default     = null
}

variable "install_plandex" {
  type        = bool
  description = "Whether to install Plandex."
  default     = true
}

variable "plandex_version" {
  type        = string
  description = "The version of Plandex to install. Use 'latest' for the most recent release, or pin a specific version like '2.2.1'."
  default     = "latest"
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key passed to Plandex via the OPENAI_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key passed to Plandex via the ANTHROPIC_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "google_api_key" {
  type        = string
  description = "Google API key passed to Plandex via the GOOGLE_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "openrouter_api_key" {
  type        = string
  description = "OpenRouter API key passed to Plandex via the OPENROUTER_API_KEY env var."
  sensitive   = true
  default     = ""
}

variable "plandex_api_host" {
  type        = string
  description = "Optional Plandex server host. Set this to your self-hosted Plandex server URL (e.g. https://plandex.example.com). Leave empty to use the public Plandex Cloud or BYO-key local mode."
  default     = ""
}

resource "coder_env" "openai_api_key" {
  count    = var.openai_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "google_api_key" {
  count    = var.google_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GOOGLE_API_KEY"
  value    = var.google_api_key
}

resource "coder_env" "openrouter_api_key" {
  count    = var.openrouter_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENROUTER_API_KEY"
  value    = var.openrouter_api_key
}

resource "coder_env" "plandex_api_host" {
  count    = var.plandex_api_host != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "PLANDEX_API_HOST"
  value    = var.plandex_api_host
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_PLANDEX_VERSION = var.plandex_version
    ARG_INSTALL_PLANDEX = tostring(var.install_plandex)
    ARG_WORKDIR         = local.workdir
  })
  module_dir_name = ".coder-modules/fran-mora/plandex"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Plandex"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

# Pass-through of coder-utils script outputs so upstream modules can serialize
# their coder_script resources behind this module's install pipeline using
# `coder exp sync want <self> <each name>`.
output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
