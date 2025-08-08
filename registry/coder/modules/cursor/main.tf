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
  default     = "/icon/cursor.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Cursor in."
  default     = "/home/coder"
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
}

variable "install_cursor_cli" {
  type        = bool
  description = "Whether to install Cursor CLI."
  default     = true
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.3.3"
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = true
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Cursor CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Cursor CLI."
  default     = null
}

locals {
  app_slug           = "cursor"
  install_script     = file("${path.module}/scripts/install.sh")
  start_script       = file("${path.module}/scripts/start.sh")
  module_dir_name    = ".cursor-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Cursor"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Cursor CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  agentapi_subdomain   = var.subdomain
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_FOLDER='${var.folder}' \
    ARG_INSTALL='${var.install_cursor_cli}' \
    /tmp/install.sh
  EOT
}

# Legacy desktop app for backward compatibility
resource "coder_app" "cursor_desktop" {
  agent_id     = var.agent_id
  external     = true
  icon         = var.icon
  slug         = "cursor-desktop"
  display_name = "Cursor Desktop"
  order        = var.order != null ? var.order + 1 : null
  group        = var.group
  url = join("", [
    "cursor://coder.coder-remote/open",
    "?owner=",
    data.coder_workspace_owner.me.name,
    "&workspace=",
    data.coder_workspace.me.name,
    var.folder != "/home/coder" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])
}

output "cursor_desktop_url" {
  value       = coder_app.cursor_desktop.url
  description = "Cursor IDE Desktop URL."
}
