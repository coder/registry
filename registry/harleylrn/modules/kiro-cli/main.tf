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
  description = "The icon to use for the install scripts."
  default     = "/icon/kiro.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Kiro CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Kiro CLI."
  default     = null
}

variable "install_kiro_cli" {
  type        = bool
  description = "Whether to install Kiro CLI. When false, a working kiro-cli must already be on PATH."
  default     = true
}

variable "kiro_cli_version" {
  type        = string
  description = "The version of Kiro CLI to install."
  default     = "latest"
}

variable "kiro_install_url" {
  type        = string
  description = "Base URL for Kiro CLI installation downloads. Defaults to https://desktop-release.q.us-east-1.amazonaws.com."
  default     = null
}

variable "auth_tarball" {
  type        = string
  description = "Base64 encoded, zstd compressed tarball of a pre-authenticated ~/.local/share/kiro-cli directory."
  default     = ""
  sensitive   = true
}

variable "api_key" {
  type        = string
  description = "Kiro API key, exported as KIRO_API_KEY. See https://kiro.dev/docs/getting-started/authentication/"
  default     = ""
  sensitive   = true
}

variable "agent_config" {
  type        = string
  description = "Optional Agent configuration JSON for Kiro CLI."
  default     = null
}

resource "coder_env" "auth_tarball" {
  count    = var.auth_tarball != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "KIRO_CLI_AUTH_TARBALL"
  value    = var.auth_tarball
}

resource "coder_env" "kiro_api_key" {
  count    = var.api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "KIRO_API_KEY"
  value    = var.api_key
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL      = tostring(var.install_kiro_cli)
    ARG_VERSION      = base64encode(var.kiro_cli_version)
    ARG_INSTALL_URL  = var.kiro_install_url != null ? base64encode(trimsuffix(var.kiro_install_url, "/")) : ""
    ARG_WORKDIR      = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_AGENT_CONFIG = var.agent_config != null ? base64encode(var.agent_config) : ""
    ARG_AGENT_NAME   = base64encode(try(jsondecode(var.agent_config).name, "agent"))
  })
  module_dir_name = ".coder-modules/harleylrn/kiro-cli"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Kiro CLI"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
