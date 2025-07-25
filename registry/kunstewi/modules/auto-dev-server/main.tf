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

variable "project_dir" {
  type        = string
  description = "The directory to check for a package.json file."
  default     = "/home/coder/project"
}

resource "coder_script" "auto_npm_start" {
  agent_id     = var.agent_id
  display_name = "Auto npm start"
  icon         = "/icon/node.svg"
  script = templatefile("${path.module}/run.sh", {
    PROJECT_DIR : var.project_dir,
  })
  run_on_start       = true
  start_blocks_login = false # Run in background, don't block login
}

