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
  default     = "/icon/goose.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
}

variable "install_goose" {
  type        = bool
  description = "Whether to install Goose with the official installer (https://goose-docs.ai/docs/getting-started/installation). When false, goose must already be on PATH."
  default     = true
}

variable "goose_version" {
  type        = string
  description = "The version of Goose to install, for example 'v1.54.0'. Use 'stable' for the latest stable release."
  default     = "stable"
}

variable "goose_provider" {
  type        = string
  description = "The provider to use for Goose (e.g., anthropic). Exported as GOOSE_PROVIDER. See https://goose-docs.ai/docs/getting-started/providers"
}

variable "goose_model" {
  type        = string
  description = "The model to use for Goose (e.g., claude-sonnet-4-6). Exported as GOOSE_MODEL."
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Goose."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Goose."
  default     = null
}

variable "additional_extensions" {
  type        = string
  description = "Extensions (MCP servers) in YAML format, keyed by name as under `extensions` in config.yaml. Added to the user config.yaml; extensions that already exist there are kept. Values are rendered into the install script, so pass secrets with env_keys and coder_env instead of envs. See https://goose-docs.ai/docs/getting-started/using-extensions"
  default     = null
}

resource "coder_env" "goose_provider" {
  agent_id = var.agent_id
  name     = "GOOSE_PROVIDER"
  value    = var.goose_provider
}

resource "coder_env" "goose_model" {
  agent_id = var.agent_id
  name     = "GOOSE_MODEL"
  value    = var.goose_model
}

locals {
  workdir               = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  additional_extensions = var.additional_extensions != null ? trimspace(var.additional_extensions) : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL       = tostring(var.install_goose)
    ARG_GOOSE_VERSION = base64encode(var.goose_version)
    ARG_WORKDIR       = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_EXTENSIONS    = local.additional_extensions != "" ? base64encode(jsonencode(yamldecode(local.additional_extensions))) : ""
  })
  module_dir_name = ".coder-modules/coder/goose"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Goose"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
