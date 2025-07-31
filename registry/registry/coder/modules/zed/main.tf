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
  description = "The ID of a Coder agent"
}

variable "agent_name" {
  type        = string
  description = "The name of the agent"
  default     = ""
}

variable "folder" {
  type        = string
  description = "The folder to open in Zed"
  default     = ""
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)"
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to"
  default     = null
}

variable "slug" {
  type        = string
  description = "The slug of the app"
  default     = "zed"
}

variable "display_name" {
  type        = string
  description = "The display name of the app"
  default     = "Zed"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  workspace_name = lower(data.coder_workspace.me.name)
  owner_name     = lower(data.coder_workspace_owner.me.name)
  agent_name     = lower(var.agent_name)
  hostname       = var.agent_name != "" ? "${local.agent_name}.${local.workspace_name}.${local.owner_name}.coder" : "${local.workspace_name}.coder"
}

resource "coder_app" "zed" {
  agent_id     = var.agent_id
  display_name = var.display_name
  slug         = var.slug
  icon         = "/icon/zed.svg"
  external     = true
  order        = var.order
  group        = var.group
  url          = "zed://ssh/${local.hostname}${var.folder}"
}

output "zed_url" {
  value       = coder_app.zed.url
  description = "Zed URL"
}
