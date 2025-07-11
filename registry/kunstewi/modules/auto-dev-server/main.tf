terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "project_dir" {
  description = "The directory to scan for projects"
  type        = string
  default     = "/home/coder"
}

variable "auto_start" {
  description = "Whether to automatically start development servers"
  type        = bool
  default     = true
}

variable "port_range_start" {
  description = "Starting port for development servers"
  type        = number
  default     = 3000
}

variable "port_range_end" {
  description = "Ending port for development servers"
  type        = number
  default     = 9000
}

variable "log_level" {
  description = "Log level for the auto-dev-server script"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR"
  }
}

locals {
  script_content = templatefile("${path.module}/scripts/auto-dev-server.sh", {
    project_dir      = var.project_dir
    auto_start       = var.auto_start
    port_range_start = var.port_range_start
    port_range_end   = var.port_range_end
    log_level        = var.log_level
  })
}

resource "coder_script" "auto_dev_server" {
  agent_id     = var.agent_id
  display_name = "Auto Development Server"
  icon         = "/icon/play.svg"
  script       = local.script_content
  run_on_start = var.auto_start
  run_on_stop  = false
  timeout      = 300
}

output "script_id" {
  description = "The ID of the auto-dev-server script"
  value       = coder_script.auto_dev_server.id
}