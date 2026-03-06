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

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "agent_name" {
  type        = string
  description = "The name of the coder_agent resource. (Only required if subdomain is false and the template uses multiple agents.)"
  default     = null
}

variable "slug" {
  type        = string
  description = "The slug of the coder_app resource."
  default     = "ttyd"
}

variable "display_name" {
  type        = string
  description = "The display name for the ttyd application."
  default     = "Web Terminal"
}

variable "port" {
  type        = number
  description = "The port to run ttyd on."
  default     = 7681
}

variable "command" {
  type        = string
  description = "The command for ttyd to run (e.g., bash, fish, htop)."
}

variable "writable" {
  type        = bool
  description = "Allow clients to write to the terminal."
  default     = true
}

variable "max_clients" {
  type        = number
  description = "Maximum number of concurrent clients (0 for unlimited)."
  default     = 0
}

variable "additional_args" {
  type        = string
  description = "Additional arguments to pass to ttyd."
  default     = ""
}

variable "log_path" {
  type        = string
  description = "The path to log ttyd output to."
  default     = "/tmp/ttyd.log"
}

variable "ttyd_version" {
  type        = string
  description = "The version of ttyd to install."
  default     = "1.7.7"
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via its own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = true
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

variable "open_in" {
  type        = string
  description = <<-EOT
    Determines where the app will be opened. Valid values are "tab" and "slim-window" (default).
    "tab" opens in a new tab in the same browser window.
    "slim-window" opens a new browser window without navigation controls.
  EOT
  default     = "slim-window"
  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

resource "coder_script" "ttyd" {
  agent_id     = var.agent_id
  display_name = var.display_name
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    PORT            = var.port,
    COMMAND         = var.command,
    WRITABLE        = var.writable,
    MAX_CLIENTS     = var.max_clients,
    ADDITIONAL_ARGS = var.additional_args,
    LOG_PATH        = var.log_path,
    VERSION         = var.ttyd_version,
    BASE_PATH       = local.base_path,
  })
  run_on_start = true
}

resource "coder_app" "ttyd" {
  count        = var.command != "" ? 1 : 0
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}${local.base_path}/"
  icon         = "/icon/terminal.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}${local.base_path}/token"
    interval  = 5
    threshold = 6
  }
}

locals {
  base_path = var.subdomain ? "" : format("/@%s/%s%s/apps/%s", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, var.agent_name != null ? ".${var.agent_name}" : "", var.slug)
}
