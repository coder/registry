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
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing the agent used by AgentAPI."
  default     = null
}

variable "start_script" {
  type        = string
  description = "Script that starts AgentAPI."
  default     = null
}

variable "agent_name" {
  type        = string
  description = "The name of the agent. This is used to construct unique script names for the experiment sync."

}

variable "module_directory" {
  type        = string
  description = "The module's working directory for the install/pre/post/start scripts this module writes. Logs land under a `logs/` subdirectory of this path."
}

variable "display_name_prefix" {
  type        = string
  description = "Prefix for each coder_script display_name. Example: setting 'Claude Code' yields 'Claude Code: Install Script', 'Claude Code: Pre-Install Script', etc. When unset, scripts show as plain 'Install Script'."
  default     = ""
}

variable "icon" {
  type        = string
  description = "Icon shown in the Coder UI for every coder_script this module creates. Falls back to the Coder provider's default when unset."
  default     = null
}

locals {
  encoded_pre_install_script  = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_install_script      = base64encode(var.install_script)
  encoded_post_install_script = var.post_install_script != null ? base64encode(var.post_install_script) : ""
  encoded_start_script        = var.start_script != null ? base64encode(var.start_script) : ""

  pre_install_script_name  = "${var.agent_name}-pre_install_script"
  install_script_name      = "${var.agent_name}-install_script"
  post_install_script_name = "${var.agent_name}-post_install_script"
  start_script_name        = "${var.agent_name}-start_script"

  pre_install_path  = "${var.module_directory}/pre_install.sh"
  install_path      = "${var.module_directory}/install.sh"
  post_install_path = "${var.module_directory}/post_install.sh"
  start_path        = "${var.module_directory}/start.sh"

  pre_install_log_path  = "${local.log_directory}/pre_install.log"
  install_log_path      = "${local.log_directory}/install.log"
  post_install_log_path = "${local.log_directory}/post_install.log"
  start_log_path        = "${local.log_directory}/start.log"

  log_directory = "${var.module_directory}/logs"

  install_sync_deps = var.pre_install_script != null ? local.pre_install_script_name : null

  start_sync_deps = (
    var.post_install_script != null
    ? "${local.install_script_name} ${local.post_install_script_name}"
    : local.install_script_name
  )

  display_name_prefix = var.display_name_prefix != "" ? "${var.display_name_prefix}: " : ""
}

resource "coder_script" "pre_install_script" {
  count        = var.pre_install_script == null ? 0 : 1
  agent_id     = var.agent_id
  display_name = "${local.display_name_prefix}Pre-Install Script"
  icon         = var.icon
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${var.module_directory}
    mkdir -p ${local.log_directory}

    trap 'coder exp sync complete ${local.pre_install_script_name}' EXIT
    coder exp sync start ${local.pre_install_script_name}

    echo -n '${local.encoded_pre_install_script}' | base64 -d > ${local.pre_install_path}
    chmod +x ${local.pre_install_path}

    ${local.pre_install_path} 2>&1 | tee ${local.pre_install_log_path}
  EOT
}

resource "coder_script" "install_script" {
  agent_id     = var.agent_id
  display_name = "${local.display_name_prefix}Install Script"
  icon         = var.icon
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${var.module_directory}
    mkdir -p ${local.log_directory}

    trap 'coder exp sync complete ${local.install_script_name}' EXIT
    %{if local.install_sync_deps != null~}
    coder exp sync want ${local.install_script_name} ${local.install_sync_deps}
    %{endif~}
    coder exp sync start ${local.install_script_name}
    echo -n '${local.encoded_install_script}' | base64 -d > ${local.install_path}
    chmod +x ${local.install_path}

    ${local.install_path} 2>&1 | tee ${local.install_log_path}
  EOT
}

resource "coder_script" "post_install_script" {
  count        = var.post_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "${local.display_name_prefix}Post-Install Script"
  icon         = var.icon
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.log_directory}

    trap 'coder exp sync complete ${local.post_install_script_name}' EXIT
    coder exp sync want ${local.post_install_script_name} ${local.install_script_name}
    coder exp sync start ${local.post_install_script_name}

    echo -n '${local.encoded_post_install_script}' | base64 -d > ${local.post_install_path}
    chmod +x ${local.post_install_path}

    ${local.post_install_path} 2>&1 | tee ${local.post_install_log_path}
  EOT
}

resource "coder_script" "start_script" {
  count        = var.start_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "${local.display_name_prefix}Start Script"
  icon         = var.icon
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    mkdir -p ${local.log_directory}

    trap 'coder exp sync complete ${local.start_script_name}' EXIT

    coder exp sync want ${local.start_script_name} ${local.start_sync_deps}
    coder exp sync start ${local.start_script_name}

    echo -n '${local.encoded_start_script}' | base64 -d > ${local.start_path}
    chmod +x ${local.start_path}

    ${local.start_path} 2>&1 | tee ${local.start_log_path}
  EOT
}

# Filtered, run-order list of the `coder exp sync` names for every
# coder_script this module actually creates. Absent scripts (pre/post/start
# when their inputs are null) are omitted entirely, not padded with empty
# strings. Downstream modules can use this with
# `coder exp sync want <self> <each of these>` to serialize their own
# scripts behind the install pipeline.
output "scripts" {
  description = "Ordered list of `coder exp sync` names for the coder_script resources this module creates, in the run order it enforces (pre_install, install, post_install, start). Scripts that were not configured are absent from the list."
  value = concat(
    var.pre_install_script != null ? [local.pre_install_script_name] : [],
    [local.install_script_name],
    var.post_install_script != null ? [local.post_install_script_name] : [],
    var.start_script != null ? [local.start_script_name] : [],
  )
}
