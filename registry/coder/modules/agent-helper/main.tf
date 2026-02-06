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
  description = "The name of the agent."

}

locals {
  encoded_pre_install_script  = var.pre_install_script != null ? base64encode(var.pre_install_script) : ""
  encoded_install_script      = var.install_script != null ? base64encode(var.install_script) : ""
  encoded_post_install_script = var.post_install_script != null ? base64encode(var.post_install_script) : ""
  agentapi_start_script_b64   = base64encode(var.start_script)

  pre_install_script_name  = var.agent_name + "-" + "pre_install_script"
  install_script_name      = var.agent_name + "-" + "install_script"
  post_install_script_name = var.agent_name + "-" + "post_install_script"
  start_script_name        = var.agent_name + "-" + "start_script"
}


resource "coder_script" "install_script" {
  agent_id     = var.agent_id
  display_name = "Install Script"
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    coder exp sync want ${local.install_script_name} ${local.pre_install_script_name}

  EOT
}
