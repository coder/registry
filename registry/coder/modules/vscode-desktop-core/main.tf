terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "folder" {
  type        = string
  description = "The folder to open in the IDE."
  default     = ""
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
}

variable "protocol" {
  type        = string
  description = "The URI protocol the IDE."
}

variable "web_app_icon" {
  type        = string
  description = "The icon of the coder_app."
}

variable "web_app_slug" {
  type        = string
  description = "The slug of the coder_app."
}

variable "web_app_display_name" {
  type        = string
  description = "The display name of the coder_app."
}

variable "web_app_order" {
  type        = number
  description = "The order of the coder_app."
  default     = null
}

variable "web_app_group" {
  type        = string
  description = "The group of the coder_app."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "vscode-desktop" {
  agent_id = var.agent_id
  external = true
  
  icon         = var.web_app_icon
  slug         = var.web_app_slug
  display_name = var.web_app_display_name

  order = var.web_app_order
  group = var.web_app_group

  url = join("", [
    var.protocol,
    "://coder.coder-remote/open",
    "?owner=",
    data.coder_workspace_owner.me.name,
    "&workspace=",
    data.coder_workspace.me.name,
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])

  /*
    url = join("", [
    "vscode://coder.coder-remote/open",
    "?owner=${data.coder_workspace_owner.me.name}",
    "&workspace=${data.coder_workspace.me.name}",
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=${data.coder_workspace.me.access_url}",
    "&token=$SESSION_TOKEN",
  ])
  */
}

output "ide_uri" {
  value       = coder_app.vscode-desktop.url
  description = "IDE URI."
}