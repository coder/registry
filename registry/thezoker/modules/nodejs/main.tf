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

resource "coder_script" "nodejs" {
  agent_id     = var.agent_id
  display_name = "Node.js:"
  script = templatefile("${path.module}/run.sh", {
    NVM_VERSION : var.nvm_version,
    INSTALL_PREFIX : var.nvm_install_prefix,
    NODE_VERSIONS : join(",", var.node_versions),
    DEFAULT : var.default_node_version,
    PRE_INSTALL_SCRIPT : var.pre_install_script != null ? var.pre_install_script : "",
    POST_INSTALL_SCRIPT : var.post_install_script != null ? var.post_install_script : "",
  })
  run_on_start       = true
  start_blocks_login = true
}
