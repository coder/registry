terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

locals {
  # A built-in icon like "/icon/code.svg" or a full URL of icon
  icon_url = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/code.svg"
  # a map of all possible values
  options = {
    "Option 1" = {
      "name"  = "Option 1",
      "value" = "1"
      "icon"  = "/emojis/1.png"
    }
    "Option 2" = {
      "name"  = "Option 2",
      "value" = "2"
      "icon"  = "/emojis/2.png"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log MODULE_NAME to."
  default     = "/tmp/MODULE_NAME.log"
}

variable "port" {
  type        = number
  description = "The port to run MODULE_NAME on."
  default     = 19999
}

variable "mutable" {
  type        = bool
  description = "Whether the parameter is mutable."
  default     = true
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}
# Add other variables here


resource "coder_script" "MODULE_NAME" {
  agent_id     = var.agent_id
  display_name = "MODULE_NAME"
  icon         = local.icon_url
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "MODULE_NAME" {
  agent_id     = var.agent_id
  slug         = "MODULE_NAME"
  display_name = "MODULE_NAME"
  url          = "http://localhost:${var.port}"
  icon         = local.icon_url
  subdomain    = false
  share        = "owner"
  order        = var.order

  # Remove if the app does not have a healthcheck endpoint
  healthcheck {
    url       = "http://localhost:${var.port}/healthz"
    interval  = 5
    threshold = 6
  }
}

data "coder_parameter" "MODULE_NAME" {
  type         = "list(string)"
  name         = "MODULE_NAME"
  display_name = "MODULE_NAME"
  icon         = local.icon_url
  mutable      = var.mutable
  default      = local.options["Option 1"]["value"]

  dynamic "option" {
    for_each = local.options
    content {
      icon  = option.value.icon
      name  = option.value.name
      value = option.value.value
    }
  }
}

