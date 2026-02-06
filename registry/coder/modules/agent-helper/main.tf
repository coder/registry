terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

data "coder_task" "me" {}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing the agent used by AgentAPI."
  default     = null
}

variable "install_script" {
  type        = string
  description = "Script to install the agent used by AgentAPI."
  default     = ""
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing the agent used by AgentAPI."
  default     = null
}

variable "start_script" {
  type        = string
  description = "Script that starts AgentAPI."
}

variable "agent_name" {
  type        = string
  description = "The name of the agent. This is used to construct unique script names for the experiment sync."

}

variable "module_dir_name" {
  type        = string
  description = "The name of the module directory."
}

locals {
  encoded_pre_install_script  = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_install_script      = var.install_script != null ? base64encode(var.install_script) : ""
  encoded_post_install_script = var.post_install_script != null ? base64encode(var.post_install_script) : ""
  encoded_start_script        = base64encode(var.start_script)

  log_file_creation_script_name = var.agent_name + "-" + "log_file_creation_script"
  pre_install_script_name       = var.agent_name + "-" + "pre_install_script"
  install_script_name           = var.agent_name + "-" + "install_script"
  post_install_script_name      = var.agent_name + "-" + "post_install_script"
  start_script_name             = var.agent_name + "-" + "start_script"

  module_dir_path = "${HOME}/${var.module_dir_name}"

  pre_install_path  = "${local.module_dir_path}/pre_install.sh"
  install_path      = "${local.module_dir_path}/install.sh"
  post_install_path = "${local.module_dir_path}/post_install.sh"
  start_path        = "${local.module_dir_path}/start.sh"

  pre_install_log_path  = "${local.module_dir_path}/pre_install.log"
  install_log_path      = "${local.module_dir_path}/install.log"
  post_install_log_path = "${local.module_dir_path}/post_install.log"
  start_log_path        = "${local.module_dir_path}/start.log"
}

resource "coder_script" "log_file_creation_script" {
  agent_id     = var.agent_id
  display_name = "Log File Creation Script"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    trap 'coder exp sync complete ${local.log_file_creation_script_name}' EXIT
    coder exp sync start ${local.log_file_creation_script_name}

    mkdir -p ${local.module_dir_path}
    if [ -n "${var.pre_install_script}" ]; then
      touch ${local.pre_install_log_path}
    fi
    touch ${local.install_log_path}
    if [ -n "${var.post_install_script}" ]; then
      touch ${local.post_install_log_path}
    fi
    touch ${local.start_log_path}
  EOT
}

resource "coder_script" "pre_install_script" {
  count        = var.pre_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Pre-Install Script"
  log_path     = local.pre_install_log_path
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    trap 'coder exp sync complete ${local.pre_install_script_name}' EXIT
    coder exp sync want ${local.pre_install_script_name} ${local.log_file_creation_script_name}
    coder exp sync start ${local.pre_install_script_name}

    echo -n '${local.encoded_pre_install_script}' | base64 -d > ${local.pre_install_path}
    chmod +x ${local.pre_install_path}

    ${local.pre_install_path}
  EOT
}

resource "coder_script" "install_script" {
  agent_id     = var.agent_id
  display_name = "Install Script"
  log_path     = local.install_log_path
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    trap 'coder exp sync complete ${local.install_script_name}' EXIT
    if [ -n "${var.pre_install_script}" ]; then
      coder exp sync want ${local.install_script_name} ${local.pre_install_script_name}
    else
      coder exp sync want ${local.install_script_name} ${local.log_file_creation_script_name}
    fi
    coder exp sync start ${local.install_script_name}
    echo -n '${base64encode(local.encoded_install_script)}' | base64 -d > ${local.install_path}
    chmod +x ${local.install_path}

    ${local.install_path}
  EOT
}

resource "coder_script" "post_install_script" {
  count        = var.post_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Post-Install Script"
  log_path     = local.post_install_log_path
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    trap 'coder exp sync complete ${local.post_install_script_name}' EXIT
    coder exp sync want ${local.post_install_script_name} ${local.install_script_name}
    coder exp sync start ${local.post_install_script_name}

    echo -n '${local.encoded_post_install_script}' | base64 -d > ${local.post_install_path}
    chmod +x ${local.post_install_path}

    ${local.post_install_path}
  EOT
}

resource "coder_script" "start_script" {
  agent_id     = var.agent_id
  display_name = "Start Script"
  log_path     = local.start_log_path
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    trap 'coder exp sync complete ${local.start_script_name}' EXIT

    if [ -n "${var.post_install_script}" ]; then
      coder exp sync want ${local.start_script_name} ${local.install_script_name} ${local.post_install_script_name}
    else
      coder exp sync want ${local.start_script_name} ${local.install_script_name}
    fi
    coder exp sync start ${local.start_script_name}

    echo -n '${base64encode(local.encoded_start_script)}' | base64 -d > ${local.start_path}
    chmod +x ${local.start_path}

    ${local.start_path}
  EOT
}
