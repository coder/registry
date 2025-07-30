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

resource "coder_script" "git-commit-signing" {
  display_name = "Git commit signing"
  icon         = "/icon/git.svg"

  script       = file("${path.module}/run.sh")
  run_on_start = true

  agent_id = var.agent_id
}
