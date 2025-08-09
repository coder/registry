terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/sourcegraph-amp.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run sourcegraph-amp in."
  default     = "/home/coder"
}

variable "install_sourcegraph-amp" {
  type        = bool
  description = "Whether to install sourcegraph-amp."
  default     = true
}

variable "sourcegraph-amp_api_key" {
  type        = string
  description = "sourcegraph-amp API Key"
  default     = ""
}

resource "coder_env" "sourcegraph-amp_api_key" {
  agent_id = var.agent_id
  name     = "SOURCEGRAPH_AMP_API_KEY"
  value    = var.sourcegraph-amp_api_key
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.3.0"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing sourcegraph-amp"
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing sourcegraph-amp."
  default     = null
}

locals {
  base_extensions = <<-EOT
coder:
  args:
  - exp
  - mcp
  - server
  cmd: coder
  description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
  enabled: true
  envs:
    CODER_MCP_APP_STATUS_SLUG: ${local.app_slug}
    CODER_MCP_AI_AGENTAPI_URL: http://localhost:3284
  name: Coder
  timeout: 3000
  type: stdio
developer:
  display_name: Developer
  enabled: true
  name: developer
  timeout: 300
  type: builtin
EOT

  app_slug        = "amp"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".sourcegraph-amp-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Sourcegraph Amp"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Sourcegraph Amp CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = <<-EOT
     #!/bin/bash
     set -o errexit
     set -o pipefail

     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
     chmod +x /tmp/start.sh
     SOURCEGRAPH_AMP_API_KEY='${var.sourcegraph-amp_api_key}' \
     SOURCEGRAPH_AMP_START_DIRECTORY='${var.folder}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL_SOURCEGRAPH_AMP='${var.install_sourcegraph-amp}' \
    SOURCEGRAPH_AMP_START_DIRECTORY='${var.folder}' \
    BASE_EXTENSIONS='${replace(local.base_extensions, "'", "'\\''")}' \
    /tmp/install.sh
  EOT
}


