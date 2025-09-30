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

variable "project_detection" {
  type        = bool
  description = "Master toggle for automatic project detection. When false, disables all project detection regardless of individual enable flags."
  default     = true
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

variable "enable_preview_app" {
  type        = bool
  description = "Enable automatic creation of a preview app for the first detected project."
  default     = true
}

# Local variables that respect the master toggle
locals {
  # Apply master toggle to all individual enables
  effective_enable_npm          = var.project_detection && var.enable_npm
  effective_enable_rails        = var.project_detection && var.enable_rails
  effective_enable_django       = var.project_detection && var.enable_django
  effective_enable_flask        = var.project_detection && var.enable_flask
  effective_enable_spring_boot  = var.project_detection && var.enable_spring_boot
  effective_enable_go           = var.project_detection && var.enable_go
  effective_enable_php          = var.project_detection && var.enable_php
  effective_enable_rust         = var.project_detection && var.enable_rust
  effective_enable_dotnet       = var.project_detection && var.enable_dotnet
  effective_enable_devcontainer = var.project_detection && var.enable_devcontainer

  # Read the detected port from the file written by the script
  detected_port = var.enable_preview_app ? try(tonumber(trimspace(file("/tmp/detected-port.txt"))), 3000) : 3000
  # Attempt to read project information for better preview naming
  detected_projects = try(jsondecode(file("/tmp/detected-projects.json")), [])
  preview_project   = length(local.detected_projects) > 0 ? local.detected_projects[0] : null
}

resource "coder_script" "auto_start_dev_server" {
  agent_id     = var.agent_id
  display_name = var.display_name
  icon         = "/icon/server.svg"
  script = templatefile("${path.module}/run.sh", {
    WORKSPACE_DIR       = var.workspace_directory
    ENABLE_NPM          = local.effective_enable_npm
    ENABLE_RAILS        = local.effective_enable_rails
    ENABLE_DJANGO       = local.effective_enable_django
    ENABLE_FLASK        = local.effective_enable_flask
    ENABLE_SPRING_BOOT  = local.effective_enable_spring_boot
    ENABLE_GO           = local.effective_enable_go
    ENABLE_PHP          = local.effective_enable_php
    ENABLE_RUST         = local.effective_enable_rust
    ENABLE_DOTNET       = local.effective_enable_dotnet
    ENABLE_DEVCONTAINER = local.effective_enable_devcontainer
    LOG_PATH            = var.log_path
    SCAN_DEPTH          = var.scan_depth
    STARTUP_DELAY       = var.startup_delay
  })
  run_on_start = true
}

# Create preview app for first detected project
resource "coder_app" "preview" {
  count        = var.enable_preview_app && var.project_detection ? 1 : 0
  agent_id     = var.agent_id
  slug         = "dev-preview"
  display_name = "Live Preview"
  url          = "http://localhost:${local.detected_port}"
  icon         = "/icon/globe.svg"
  subdomain    = true
  share        = "owner"
}

# Output to expose detected projects
output "detected_projects_file" {
  value       = "/tmp/detected-projects.json"
  description = "Path to JSON file containing detected projects with their types, ports, and commands"
}

output "log_path" {
  value       = var.log_path
  description = "Path to the log file for dev server output"
}

# Example output values for common port mappings
output "common_ports" {
  value = {
    nodejs = 3000
    rails  = 3000
    django = 8000
    flask  = 5000
    spring = 8080
    go     = 8080
    php    = 8080
    rust   = 8000
    dotnet = 5000
  }
  description = "Common default ports for different project types"
}

output "preview_url" {
  value       = var.enable_preview_app && var.project_detection ? try(coder_app.preview[0].url, null) : null
  description = "URL of the live preview app (if enabled)"
}

output "detected_port" {
  value       = local.detected_port
  description = "Port of the first detected development server"
}