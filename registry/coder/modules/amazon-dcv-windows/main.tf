terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "admin_password" {
  type      = string
  default   = "coderDCV!"
  sensitive = true
}

variable "port" {
  type        = number
  description = "The port number for the DCV server."
  default     = 8443
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for the DCV server."
  default     = true
}

variable "slug" {
  type        = string
  description = "The slug of the web-dcv coder_app resource."
  default     = "web-dcv"
}

resource "coder_app" "web-dcv" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = "Web DCV"
  url          = "https://localhost:${var.port}${local.web_url_path}?username=${local.admin_username}&password=${var.admin_password}"
  icon         = "/icon/dcv.svg"
  subdomain    = var.subdomain
}

resource "coder_script" "install-dcv" {
  agent_id     = var.agent_id
  display_name = "Install DCV"
  icon         = "/icon/dcv.svg"
  run_on_start = true
  script = templatefile("${path.module}/install-dcv.ps1", {
    admin_password : var.admin_password,
    port : var.port,
    web_url_path : local.web_url_path
  })
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  web_url_path   = var.subdomain ? "/" : format("/@%s/%s/apps/%s", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, var.slug)
  admin_username = "Administrator"
}

output "web_url_path" {
  value = local.web_url_path
}

output "username" {
  value = local.admin_username
}

output "password" {
  value     = var.admin_password
  sensitive = true
}

output "port" {
  value = var.port
}
