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
  encoded_pre_install_script  = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_post_install_script = var.post_install_script != null ? base64encode(var.post_install_script) : ""

  install_script = templatefile("${path.module}/run.sh", {
    NVM_VERSION    = var.nvm_version,
    INSTALL_PREFIX = var.nvm_install_prefix,
    NODE_VERSIONS  = join(",", var.node_versions),
    DEFAULT        = var.default_node_version,
  })
  encoded_install_script = base64encode(local.install_script)

  pre_install_script_name  = "nodejs-pre_install_script"
  install_script_name      = "nodejs-install_script"
  post_install_script_name = "nodejs-post_install_script"

  module_dir_path = "$HOME/.nodejs-module"

  pre_install_path      = "${local.module_dir_path}/pre_install.sh"
  pre_install_log_path  = "${local.module_dir_path}/pre_install.log"
  install_path          = "${local.module_dir_path}/install.sh"
  install_log_path      = "${local.module_dir_path}/install.log"
  post_install_path     = "${local.module_dir_path}/post_install.sh"
  post_install_log_path = "${local.module_dir_path}/post_install.log"
}

resource "coder_script" "pre_install_script" {
  count        = var.pre_install_script == null ? 0 : 1
  agent_id     = var.agent_id
  display_name = "Node.js: Pre-Install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.module_dir_path}

    trap 'coder exp sync complete ${local.pre_install_script_name}' EXIT
    coder exp sync start ${local.pre_install_script_name}

    echo -n '${local.encoded_pre_install_script}' | base64 -d > ${local.pre_install_path}
    chmod +x ${local.pre_install_path}

    ${local.pre_install_path} 2>&1 | tee ${local.pre_install_log_path}
  EOT
}

resource "coder_script" "nodejs" {
  agent_id           = var.agent_id
  display_name       = "Node.js: Install"
  script             = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.module_dir_path}

    trap 'coder exp sync complete ${local.install_script_name}' EXIT
    %{if var.pre_install_script != null~}
    coder exp sync want ${local.install_script_name} ${local.pre_install_script_name}
    %{endif~}
    coder exp sync start ${local.install_script_name}

    echo -n '${local.encoded_install_script}' | base64 -d > ${local.install_path}
    chmod +x ${local.install_path}

    ${local.install_path} 2>&1 | tee ${local.install_log_path}
  EOT
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_script" "post_install_script" {
  count        = var.post_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Node.js: Post-Install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.module_dir_path}

    trap 'coder exp sync complete ${local.post_install_script_name}' EXIT
    coder exp sync want ${local.post_install_script_name} ${local.install_script_name}
    coder exp sync start ${local.post_install_script_name}

    echo -n '${local.encoded_post_install_script}' | base64 -d > ${local.post_install_path}
    chmod +x ${local.post_install_path}

    ${local.post_install_path} 2>&1 | tee ${local.post_install_log_path}
  EOT
}

output "pre_install_script_name" {
  description = "The name of the pre-install script for coder exp sync coordination."
  value       = local.pre_install_script_name
}

output "install_script_name" {
  description = "The name of the install script for coder exp sync coordination."
  value       = local.install_script_name
}

output "post_install_script_name" {
  description = "The name of the post-install script for coder exp sync coordination."
  value       = local.post_install_script_name
}
