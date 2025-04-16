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

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "agent_name" {
  type        = string
  description = "The name of the coder_agent resource. (Only required if subdomain is false and the template uses multiple agents.)"
  default     = null
}

variable "database_path" {
  type        = string
  description = "The path to the filebrowser database."
  default     = "filebrowser.db"
  validation {
    # Ensures path leads to */filebrowser.db
    condition     = can(regex(".*filebrowser\\.db$", var.database_path))
    error_message = "The database_path must end with 'filebrowser.db'."
  }
}

variable "log_path" {
  type        = string
  description = "The path to log filebrowser to."
  default     = "/tmp/filebrowser.log"
}

variable "port" {
  type        = number
  description = "The port to run filebrowser on."
  default     = 13339
}

variable "folder" {
  type        = string
  description = "--root value for filebrowser."
  default     = "~"
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "slug" {
  type        = string
  description = "The slug of the coder_app resource."
  default     = "filebrowser"
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = true
}

resource "coder_script" "filebrowser" {
  agent_id     = var.agent_id
  display_name = "File Browser"
  icon         = "/icon/filebrowser.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port,
    FOLDER : var.folder,
    LOG_PATH : var.log_path,
    DB_PATH : var.database_path,
    SUBDOMAIN : var.subdomain,
    SERVER_BASE_PATH : local.server_base_path
  })
  run_on_start = true
}

resource "coder_app" "filebrowser" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = "File Browser"
  url          = local.url
  icon         = "/icon/filebrowser.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order

  healthcheck {
    url       = local.healthcheck_url
    interval  = 5
    threshold = 6
  }
}

locals {
  server_base_path = var.subdomain ? "" : format("/@%s/%s%s/apps/%s", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, var.agent_name != null ? ".${var.agent_name}" : "", var.slug)
  url              = "http://localhost:${var.port}${local.server_base_path}"
  healthcheck_url  = "http://localhost:${var.port}${local.server_base_path}/health"
}