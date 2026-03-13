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

variable "zellij_version" {
  type        = string
  description = "The version of zellij to install."
  default     = "0.43.1"
}

variable "zellij_config" {
  type        = string
  description = "Custom zellij configuration to apply."
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

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/zellij.svg"
}

variable "mode" {
  type        = string
  description = "How to run zellij: 'web' for web client with subdomain proxy, 'terminal' for Coder built-in terminal."
  default     = "terminal"

  validation {
    condition     = contains(["web", "terminal"], var.mode)
    error_message = "mode must be 'web' or 'terminal'."
  }
}

variable "web_port" {
  type        = number
  description = "The port for the zellij web server. Only used when mode is 'web'."
  default     = 8082
}


resource "coder_script" "zellij" {
  agent_id     = var.agent_id
  display_name = "Zellij"
  icon         = "/icon/zellij.svg"
  script = templatefile("${path.module}/scripts/run.sh", {
    ZELLIJ_VERSION = var.zellij_version
    ZELLIJ_CONFIG  = var.zellij_config
    MODE           = var.mode
    WEB_PORT       = var.web_port
  })
  run_on_start = true
  run_on_stop  = false
}

# Web mode: subdomain proxy to zellij web server
resource "coder_app" "zellij_web" {
  count = var.mode == "web" ? 1 : 0

  agent_id     = var.agent_id
  slug         = "zellij"
  display_name = "Zellij"
  icon         = var.icon
  order        = var.order
  group        = var.group
  url          = "http://localhost:${var.web_port}"
  subdomain    = true
}

# Terminal mode: run zellij in Coder built-in terminal
resource "coder_app" "zellij_terminal" {
  count = var.mode == "terminal" ? 1 : 0

  agent_id     = var.agent_id
  slug         = "zellij"
  display_name = "Zellij"
  icon         = var.icon
  order        = var.order
  group        = var.group
  command      = "zellij attach --create default"
}
