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

variable "port" {
  type        = number
  description = "The port to run cmux on."
  default     = 4000
}

variable "display_name" {
  type        = string
  description = "The display name for the cmux application."
  default     = "cmux"
}

variable "slug" {
  type        = string
  description = "The slug for the cmux application."
  default     = "cmux"
}

variable "install_prefix" {
  type        = string
  description = "The prefix to install cmux to."
  default     = "/tmp/cmux"
}

variable "log_path" {
  type        = string
  description = "The path to log cmux to."
  default     = "/tmp/cmux.log"
}

variable "install_version" {
  type        = string
  description = "The version of cmux to install."
  default     = "latest"
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

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "offline" {
  type        = bool
  description = "Just run cmux in the background; do not install from the network"
  default     = false
}

variable "use_cached" {
  type        = bool
  description = "Use cached copy of cmux if present; otherwise install from npm"
  default     = false
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = false
}

variable "open_in" {
  type        = string
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window" (default)`.
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  default     = "slim-window"
  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

resource "coder_script" "cmux" {
  agent_id     = var.agent_id
  display_name = "cmux"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    VERSION : var.install_version,
    PORT : var.port,
    LOG_PATH : var.log_path,
    INSTALL_PREFIX : var.install_prefix,
    OFFLINE : var.offline,
    USE_CACHED : var.use_cached,
  })
  run_on_start = true

  lifecycle {
    precondition {
      condition     = !var.offline || !var.use_cached
      error_message = "Offline and Use Cached can not be used together"
    }
  }
}

resource "coder_app" "cmux" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}"
  icon         = "/icon/terminal.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 6
  }
}
