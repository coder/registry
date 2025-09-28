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

variable "share" {
  type        = string
  description = "The sharing level for the Parsec app."
  default     = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "parsec_version" {
  type        = string
  description = "Version of Parsec to install."
  default     = "latest"
}

variable "server_id" {
  type        = string
  description = "Custom server ID for Parsec. If not provided, a random ID will be generated."
  default     = ""
}

variable "peer_id" {
  type        = string
  description = "Custom peer ID for Parsec. If not provided, a random ID will be generated."
  default     = ""
}

data "coder_workspace" "me" {}

resource "coder_script" "parsec" {
  agent_id     = var.agent_id
  display_name = "Parsec"
  icon         = "/icon/desktop.svg"
  run_on_start = true
  script = templatefile("${path.module}/run.sh", {
    PARSEC_VERSION = var.parsec_version
    SERVER_ID      = var.server_id
    PEER_ID        = var.peer_id
  })
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = "parsec"
  display_name = "Parsec"
  url          = "http://localhost:8000"
  icon         = "/icon/desktop.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:8000"
    interval  = 5
    threshold = 15
  }
}
