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

variable "session_name" {
  type        = string
  description = "The name of the tmux session to create."
  default     = "workspace"
}

variable "startup_command" {
  type        = string
  description = "Command to run when the tmux session starts."
  default     = ""
}

variable "tmux_config" {
  type        = string
  description = "Custom tmux configuration to apply."
  default     = ""
}

variable "auto_attach" {
  type        = bool
  description = "Whether to automatically attach to the tmux session when the app starts."
  default     = true
}

variable "save_interval" {
  type        = number
  description = "Save interval (in minutes)."
  default     = 1
}

resource "coder_script" "tmux" {
  agent_id     = var.agent_id
  display_name = "tmux"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    SESSION_NAME    = var.session_name
    STARTUP_COMMAND = var.startup_command
    TMUX_CONFIG     = var.tmux_config
    AUTO_ATTACH     = var.auto_attach
    SAVE_INTERVAL   = var.save_interval
  })
  run_on_start = true
  run_on_stop  = false
}