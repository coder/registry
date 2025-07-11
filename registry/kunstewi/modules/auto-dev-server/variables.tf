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
}