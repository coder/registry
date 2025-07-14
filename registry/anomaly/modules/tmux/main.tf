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

resource "coder_script" "tmux" {
  agent_id     = var.agent_id
  display_name = "tmux"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    TMUX_CONFIG   = var.tmux_config
    SAVE_INTERVAL = var.save_interval
  })
  run_on_start = true
  run_on_stop  = false
}