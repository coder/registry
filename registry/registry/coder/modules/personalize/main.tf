terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "path" {
  type        = string
  description = "The path to a script that will be ran on start enabling a user to personalize their workspace."
  default     = "~/personalize"
}

variable "log_path" {
  type        = string
  description = "The path to a log file that will contain the output of the personalize script."
  default     = "~/personalize.log"
}

resource "coder_script" "personalize" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : var.path,
  })
  display_name       = "Personalize"
  icon               = "/icon/personalize.svg"
  log_path           = var.log_path
  run_on_start       = true
  start_blocks_login = true
}
