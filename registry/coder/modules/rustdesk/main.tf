terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

locals {
  # A built-in icon like "/icon/code.svg" or a full URL of icon
  icon_url = "https://upload.wikimedia.org/wikipedia/commons/9/96/Rustdesk.svg"
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log rustdesk to."
  default     = "/tmp/rustdesk.log"
}

variable "port" {
  type        = number
  description = "The port to run rustdesk on."
  default     = 19999
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

resource "coder_script" "rustdesk" {
  count = 1
  agent_id     = var.agent_id
  display_name = "Rustdesk"
  icon         = local.icon_url
  script = templatefile("${path.module}/run.sh", {})
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "rustdesk" {
  count = 1
  agent_id     = var.agent_id
  slug         = "rustdesk"
  display_name = "Rustdesk"
  url          = "https://rustdesk.com/web"
  icon         = local.icon_url
  order        = var.order
  external     = true
}

