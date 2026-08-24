terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "nvm_version" {
  type        = string
  description = "The version of nvm to install."
  default     = "master"
}

variable "nvm_install_prefix" {
  type        = string
  description = "The prefix to install nvm to (relative to $HOME)."
  default     = ".nvm"
}

variable "node_versions" {
  type        = list(string)
  description = "A list of Node.js versions to install."
  default     = ["node"]
}

variable "default_node_version" {
  type        = string
  description = "The default Node.js version"
  default     = "node"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Node.js."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Node.js."
  default     = null
}

locals {
  install_script = templatefile("${path.module}/run.sh", {
    NVM_VERSION    = var.nvm_version,
    INSTALL_PREFIX = var.nvm_install_prefix,
    NODE_VERSIONS  = join(",", var.node_versions),
    DEFAULT        = var.default_node_version,
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/thezoker/nodejs"
  display_name_prefix = "Node.js"
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
