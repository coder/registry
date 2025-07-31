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

variable "tmux_config" {
  type        = string
  description = "Custom tmux configuration to apply."
  default     = ""
}

variable "save_interval" {
  type        = number
  description = "Save interval (in minutes)."
  default     = 1
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
  default     = "/icon/tmux.svg"
}

variable "sessions" {
  type        = list(string)
  description = "List of tmux sessions to create or start."
  default     = ["default"]
}

resource "coder_script" "tmux" {
  agent_id     = var.agent_id
  display_name = "tmux"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/scripts/run.sh", {
    TMUX_CONFIG   = var.tmux_config
    SAVE_INTERVAL = var.save_interval
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "tmux_sessions" {
  for_each = toset(var.sessions)

  agent_id     = var.agent_id
  slug         = "tmux-${each.value}"
  display_name = "tmux - ${each.value}"
  icon         = var.icon
  order        = var.order
  group        = var.group

  command = templatefile("${path.module}/scripts/start.sh", {
    SESSION_NAME = each.value
  })
}
