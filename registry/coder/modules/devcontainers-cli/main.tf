terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "start_blocks_login " {
  type        = string
  default     = false
  description = "Boolean, This option determines whether users can log in immediately or must wait for the workspace to finish running this script upon startup."
}

resource "coder_script" "devcontainers-cli" {
  agent_id     = var.agent_id
  display_name = "devcontainers-cli"
  icon         = "/icon/devcontainers.svg"
  script       = templatefile("${path.module}/run.sh", {})
  run_on_start = true
  start_blocks_login = var.start_blocks_login
  start_blocks_login
}
