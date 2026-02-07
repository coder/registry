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

# variable "cli_app" {
#   type        = bool
#   description = "Whether to create the CLI workspace app."
#   default     = false
# }
#
# variable "cli_app_order" {
#   type        = number
#   description = "The order of the CLI workspace app."
#   default     = null
# }
#
# variable "cli_app_group" {
#   type        = string
#   description = "The group of the CLI workspace app."
#   default     = null
# }
#
# variable "cli_app_icon" {
#   type        = string
#   description = "The icon to use for the app."
#   default     = "/icon/claude.svg"
# }
#
# variable "cli_app_display_name" {
#   type        = string
#   description = "The display name of the CLI workspace app."
# }
#
# variable "cli_app_slug" {
#   type        = string
#   description = "The slug of the CLI workspace app."
# }
#
# variable "report_tasks" {
#   type        = bool
#   description = "Whether to enable task reporting."
#   default     = true
# }

locals {
  encoded_pre_install_script  = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_install_script      = var.install_script != null ? base64encode(var.install_script) : ""
  encoded_post_install_script = var.post_install_script != null ? base64encode(var.post_install_script) : ""
  encoded_start_script        = base64encode(var.start_script)

  log_file_creation_script_name = "${var.agent_name}-log_file_creation_script"
  pre_install_script_name       = "${var.agent_name}-pre_install_script"
  install_script_name           = "${var.agent_name}-install_script"
  post_install_script_name      = "${var.agent_name}-post_install_script"
  start_script_name             = "${var.agent_name}-start_script"
  agent_cli_app_name            = "${var.agent_name}-cli_app"

  module_dir_path = "$HOME/${var.module_dir_name}"

  pre_install_path  = "${local.module_dir_path}/pre_install.sh"
  install_path      = "${local.module_dir_path}/install.sh"
  post_install_path = "${local.module_dir_path}/post_install.sh"
  start_path        = "${local.module_dir_path}/start.sh"
  # agent_cli_path    = "${local.module_dir_path}/agent-command.sh"

  pre_install_log_path  = "${local.module_dir_path}/pre_install.log"
  install_log_path      = "${local.module_dir_path}/install.log"
  post_install_log_path = "${local.module_dir_path}/post_install.log"
  start_log_path        = "${local.module_dir_path}/start33.log"
}

resource "coder_script" "log_file_creation_script" {
  agent_id     = var.agent_id
  display_name = "Log File Creation Script"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    # set -o errexit
    # set -o pipefail
    set -x

    touch /tmp/meow.log
    #
    # printf "[DEBUG] Starting log_file_creation_script\n"
    # trap 'coder exp sync complete ${local.log_file_creation_script_name}' EXIT
    # printf "[DEBUG] Setting up trap for log_file_creation_script\n"
    # coder exp sync start ${local.log_file_creation_script_name}
    # printf "[DEBUG] Started sync for log_file_creation_script\n"
    #
    # printf "[DEBUG] Creating module directory: ${local.module_dir_path}\n"
    # mkdir -p ${local.module_dir_path}
    # %{if var.pre_install_script != null~}
    # printf "[DEBUG] Creating pre_install log file: ${local.pre_install_log_path}\n"
    # touch ${local.pre_install_log_path}
    # %{endif~}
    # printf "[DEBUG] Creating install log file: ${local.install_log_path}\n"
    # touch ${local.install_log_path}
    # %{if var.post_install_script != null~}
    # printf "[DEBUG] Creating post_install log file: ${local.post_install_log_path}\n"
    # touch ${local.post_install_log_path}
    # %{endif~}
    # printf "[DEBUG] Creating start log file: ${local.start_log_path}\n"
    # touch ${local.start_log_path}
    # printf "[DEBUG] Completed log_file_creation_script\n"
  EOT
}

resource "coder_script" "pre_install_script" {
  count        = var.pre_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Pre-Install Script"
  run_on_start = true
  log_path     = local.pre_install_log_path
  script       = <<-EOT
    #!/bin/bash
    # set -o errexit
    # set -o pipefail
    set -x

    printf "[DEBUG] Starting pre_install_script\n"
    trap 'coder exp sync complete ${local.pre_install_script_name}' EXIT
    printf "[DEBUG] Setting up trap for pre_install_script\n"
    coder exp sync want ${local.pre_install_script_name} ${local.log_file_creation_script_name}
    printf "[DEBUG] Waiting for log_file_creation_script dependency\n"
    coder exp sync start ${local.pre_install_script_name}
    printf "[DEBUG] Started sync for pre_install_script\n"

    printf "[DEBUG] Decoding pre_install script to: ${local.pre_install_path}\n"
    echo -n '${local.encoded_pre_install_script}' | base64 -d > ${local.pre_install_path}
    printf "[DEBUG] Setting execute permissions on pre_install script\n"
    chmod +x ${local.pre_install_path}

    printf "[DEBUG] Executing pre_install script\n"
    ${local.pre_install_path}
    printf "[DEBUG] Completed pre_install script execution\n"
  EOT
}

resource "coder_script" "install_script" {
  agent_id     = var.agent_id
  display_name = "Install Script"
  log_path     = local.install_log_path
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    # set -o errexit
    # set -o pipefail
    set -x

    printf "[DEBUG] Starting install_script\n"
    # trap 'coder exp sync complete ${local.install_script_name}' EXIT
    # printf "[DEBUG] Setting up trap for install_script\n"
    # %{if var.pre_install_script != null~}
    #   printf "[DEBUG] Waiting for pre_install_script dependency\n"
    #   coder exp sync want ${local.install_script_name} ${local.pre_install_script_name}
    # %{else~}
    #   printf "[DEBUG] Waiting for log_file_creation_script dependency\n"
    #   coder exp sync want ${local.install_script_name} ${local.log_file_creation_script_name}
    # %{endif~}
    # coder exp sync start ${local.install_script_name}
    printf "[DEBUG] Started sync for install_script\n"
    printf "[DEBUG] Decoding install script to: ${local.install_path}\n"
    echo -n '${local.encoded_install_script}' | base64 -d > ${local.install_path}
    printf "[DEBUG] Setting execute permissions on install script\n"
    chmod +x ${local.install_path}

    printf "[DEBUG] Executing install script\n"
    ${local.install_path}
    printf "[DEBUG] Completed install script execution\n"
  EOT
}

resource "coder_script" "post_install_script" {
  count        = var.post_install_script != null ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Post-Install Script"
  log_path     = local.post_install_log_path
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    # set -o errexit
    # set -o pipefail
    set -x

    printf "[DEBUG] Starting post_install_script\n"
    trap 'coder exp sync complete ${local.post_install_script_name}' EXIT
    printf "[DEBUG] Setting up trap for post_install_script\n"
    coder exp sync want ${local.post_install_script_name} ${local.install_script_name}
    printf "[DEBUG] Waiting for install_script dependency\n"
    coder exp sync start ${local.post_install_script_name}
    printf "[DEBUG] Started sync for post_install_script\n"

    printf "[DEBUG] Decoding post_install script to: ${local.post_install_path}\n"
    echo -n '${local.encoded_post_install_script}' | base64 -d > ${local.post_install_path}
    printf "[DEBUG] Setting execute permissions on post_install script\n"
    chmod +x ${local.post_install_path}

    printf "[DEBUG] Executing post_install script\n"
    ${local.post_install_path}
    printf "[DEBUG] Completed post_install script execution\n"
  EOT
}

resource "coder_script" "start_script" {
  agent_id     = var.agent_id
  display_name = "Start Script"
  log_path     = local.start_log_path
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    # set -o errexit
    # set -o pipefail
    set -x

    printf "[DEBUG] Starting start_script\n"
    trap 'coder exp sync complete ${local.start_script_name}' EXIT
    printf "[DEBUG] Setting up trap for start_script\n"

    %{if var.post_install_script != null~}
    printf "[DEBUG] Waiting for install_script and post_install_script dependencies\n"
    coder exp sync want ${local.start_script_name} ${local.install_script_name} ${local.post_install_script_name}
    %{else~}
    printf "[DEBUG] Waiting for install_script dependency\n"
    coder exp sync want ${local.start_script_name} ${local.install_script_name}
    %{endif~}
    coder exp sync start ${local.start_script_name}
    printf "[DEBUG] Started sync for start_script\n"

    printf "[DEBUG] Decoding start script to: ${local.start_path}\n"
    echo -n '${local.encoded_start_script}' | base64 -d > ${local.start_path}
    printf "[DEBUG] Setting execute permissions on start script\n"
    chmod +x ${local.start_path}

    printf "[DEBUG] Executing start script\n"
    ${local.start_path}
    printf "[DEBUG] Completed start script execution\n"
  EOT
}

# resource "coder_app" "agent_cli" {
#   count = (!var.report_tasks && var.cli_app) ? 1 : 0
#
#   slug         = var.cli_app_slug
#   display_name = var.cli_app_display_name
#   agent_id     = var.agent_id
#   command      = <<-EOT
#     #!/bin/bash
#     set -o errexit
#     set -o pipefail
#     trap 'coder exp sync complete ${local.agent_cli_app_name}' EXIT
#     coder exp sync want ${local.agent_cli_app_name} ${local.start_script_name}
#     coder exp sync start ${local.agent_cli_app_name}
#
#     ${local.agent_cli_path}
#     EOT
#   icon         = var.cli_app_icon
#   order        = var.cli_app_order
#   group        = var.cli_app_group
# }
