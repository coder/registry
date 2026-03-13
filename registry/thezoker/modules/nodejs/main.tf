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
  description = "Custom script to run before installing Node.js. Can be used for dependency ordering between modules."
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

  module_dir_path = "$HOME/.nodejs-module"

  pre_install_script_name  = "nodejs-pre_install_script"
  install_script_name      = "nodejs-install_script"
  post_install_script_name = "nodejs-post_install_script"
}

resource "coder_script" "nodejs_pre_install" {
  count        = var.pre_install_script != null ? 1 : 0
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

    echo -n '${local.encoded_pre_install_script}' | base64 -d > ${local.module_dir_path}/pre_install.sh
    chmod +x ${local.module_dir_path}/pre_install.sh

    ${local.module_dir_path}/pre_install.sh 2>&1
  EOT
}

resource "coder_script" "nodejs" {
  agent_id     = var.agent_id
  display_name = "Node.js: Install"
  run_on_start = true
  script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.module_dir_path}

    trap 'coder exp sync complete ${local.install_script_name}' EXIT
    %{if var.pre_install_script != null~}
    coder exp sync want ${local.install_script_name} ${local.pre_install_script_name}
    %{endif~}
    coder exp sync start ${local.install_script_name}

    echo -n '${base64encode(templatefile("${path.module}/run.sh", {
  NVM_VERSION    = var.nvm_version,
  INSTALL_PREFIX = var.nvm_install_prefix,
  NODE_VERSIONS  = join(",", var.node_versions),
  DEFAULT        = var.default_node_version,
}))}' | base64 -d > ${local.module_dir_path}/install.sh
    chmod +x ${local.module_dir_path}/install.sh

    ${local.module_dir_path}/install.sh 2>&1
  EOT

  start_blocks_login = true
}

resource "coder_script" "nodejs_post_install" {
  count        = var.post_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Node.js: Post-Install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    trap 'coder exp sync complete ${local.post_install_script_name}' EXIT
    coder exp sync want ${local.post_install_script_name} ${local.install_script_name}
    coder exp sync start ${local.post_install_script_name}

    echo -n '${local.encoded_post_install_script}' | base64 -d > ${local.module_dir_path}/post_install.sh
    chmod +x ${local.module_dir_path}/post_install.sh

    ${local.module_dir_path}/post_install.sh 2>&1
  EOT
}

output "pre_install_script_name" {
  description = "The name of the pre-install script for sync."
  value       = local.pre_install_script_name
}

output "install_script_name" {
  description = "The name of the install script for sync."
  value       = local.install_script_name
}

output "post_install_script_name" {
  description = "The name of the post-install script for sync."
  value       = local.post_install_script_name
}
