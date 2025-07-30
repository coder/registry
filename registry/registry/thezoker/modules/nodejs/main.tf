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

resource "coder_script" "nodejs" {
  agent_id     = var.agent_id
  display_name = "Node.js:"
  script = templatefile("${path.module}/run.sh", {
    NVM_VERSION : var.nvm_version,
    INSTALL_PREFIX : var.nvm_install_prefix,
    NODE_VERSIONS : join(",", var.node_versions),
    DEFAULT : var.default_node_version,
  })
  run_on_start       = true
  start_blocks_login = true
}
