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

variable "workspace_directory" {
  type        = string
  description = "The directory to scan for development projects."
  default     = "$HOME"
}

variable "enable_npm" {
  type        = bool
  description = "Enable auto-detection and startup of npm projects."
  default     = true
}

variable "enable_rails" {
  type        = bool
  description = "Enable auto-detection and startup of Rails projects."
  default     = true
}

variable "enable_django" {
  type        = bool
  description = "Enable auto-detection and startup of Django projects."
  default     = true
}

variable "enable_flask" {
  type        = bool
  description = "Enable auto-detection and startup of Flask projects."
  default     = true
}

variable "enable_spring_boot" {
  type        = bool
  description = "Enable auto-detection and startup of Spring Boot projects."
  default     = true
}

variable "enable_go" {
  type        = bool
  description = "Enable auto-detection and startup of Go projects."
  default     = true
}

variable "enable_php" {
  type        = bool
  description = "Enable auto-detection and startup of PHP projects."
  default     = true
}

variable "enable_rust" {
  type        = bool
  description = "Enable auto-detection and startup of Rust projects."
  default     = true
}

variable "enable_dotnet" {
  type        = bool
  description = "Enable auto-detection and startup of .NET projects."
  default     = true
}

variable "enable_devcontainer" {
  type        = bool
  description = "Enable integration with devcontainer.json configuration."
  default     = true
}

variable "log_path" {
  type        = string
  description = "The path to log development server output to."
  default     = "/tmp/dev-servers.log"
}

variable "scan_depth" {
  type        = number
  description = "Maximum directory depth to scan for projects (1-5)."
  default     = 2
  validation {
    condition     = var.scan_depth >= 1 && var.scan_depth <= 5
    error_message = "Scan depth must be between 1 and 5."
  }
}

variable "startup_delay" {
  type        = number
  description = "Delay in seconds before starting dev servers (allows other setup to complete)."
  default     = 10
}

variable "display_name" {
  type        = string
  description = "Display name for the auto-start dev server script."
  default     = "Auto-Start Dev Servers"
}

resource "coder_script" "auto_start_dev_server" {
  agent_id     = var.agent_id
  display_name = var.display_name
  icon         = "/icon/server.svg"
  script = templatefile("${path.module}/run.sh", {
    WORKSPACE_DIR         = var.workspace_directory
    ENABLE_NPM           = var.enable_npm
    ENABLE_RAILS         = var.enable_rails
    ENABLE_DJANGO        = var.enable_django
    ENABLE_FLASK         = var.enable_flask
    ENABLE_SPRING_BOOT   = var.enable_spring_boot
    ENABLE_GO            = var.enable_go
    ENABLE_PHP           = var.enable_php
    ENABLE_RUST          = var.enable_rust
    ENABLE_DOTNET        = var.enable_dotnet
    ENABLE_DEVCONTAINER  = var.enable_devcontainer
    LOG_PATH             = var.log_path
    SCAN_DEPTH           = var.scan_depth
    STARTUP_DELAY        = var.startup_delay
  })
  run_on_start = true
}