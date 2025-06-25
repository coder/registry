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
  description = "The folder to open in Fleet IDE."
  default     = ""
}

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

variable "slug" {
  type        = string
  description = "The slug of the app."
  default     = "fleet"
}

variable "display_name" {
  type        = string
  description = "The display name of the app."
  default     = "Fleet IDE"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "fleet" {
  agent_id     = var.agent_id
  external     = true
  icon         = "/icon/fleet.svg"
  slug         = var.slug
  display_name = var.display_name
  order        = var.order
  group        = var.group
  url = join("", [
    "fleet://fleet.ssh/",
    data.coder_workspace.me.access_url,
    "?",
    var.folder != "" ? join("", ["pwd=", var.folder, "&"]) : "",
    "forceNewHost=true"
  ])
}

output "fleet_url" {
  value       = coder_app.fleet.url
  description = "Fleet IDE connection URL."
}
