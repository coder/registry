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
  description = "The ID of a Coder agent."
  type        = string
}

variable "project_dir" {
  description = "The directory to scan for development projects. Defaults to $HOME."
  type        = string
  default     = "$HOME"
}

variable "enabled_frameworks" {
  description = "List of frameworks to detect and auto-start. Available: nodejs, rails, django, flask, fastapi, spring, go, rust, php"
  type        = list(string)
  default     = ["nodejs", "rails", "django", "flask", "fastapi", "spring", "go", "rust", "php"]
  
  validation {
    condition = alltrue([
      for framework in var.enabled_frameworks : 
      contains(["nodejs", "rails", "django", "flask", "fastapi", "spring", "go", "rust", "php"], framework)
    ])
    error_message = "Invalid framework. Allowed values: nodejs, rails, django, flask, fastapi, spring, go, rust, php"
  }
}

variable "start_delay" {
  description = "Delay in seconds before starting dev servers (to allow workspace to fully initialize)"
  type        = number
  default     = 30
}

variable "log_level" {
  description = "Log level for auto-dev-server. Options: DEBUG, INFO, WARN, ERROR"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR"
  }
}

variable "use_devcontainer" {
  description = "Enable devcontainer.json integration for custom startup commands"
  type        = bool
  default     = true
}

variable "custom_commands" {
  description = "Custom startup commands per framework type"
  type        = map(string)
  default     = {}
}

locals {
  # Default commands for each framework
  default_commands = {
    nodejs   = "npm start"
    rails    = "rails server"
    django   = "python manage.py runserver 0.0.0.0:8000"
    flask    = "flask run --host=0.0.0.0"
    fastapi  = "uvicorn main:app --host 0.0.0.0 --port 8000"
    spring   = "./mvnw spring-boot:run"
    go       = "go run ."
    rust     = "cargo run"
    php      = "php -S 0.0.0.0:8000"
  }
  
  # Merge custom commands with defaults
  framework_commands = merge(local.default_commands, var.custom_commands)
  
  # Detection patterns for each framework
  detection_patterns = {
    nodejs   = "package.json"
    rails    = "Gemfile|config.ru|app/controllers"
    django   = "manage.py|settings.py"
    flask    = "app.py|application.py|wsgi.py"
    fastapi  = "main.py|app.py"
    spring   = "pom.xml|build.gradle|src/main/java"
    go       = "go.mod|main.go"
    rust     = "Cargo.toml|src/main.rs"
    php      = "index.php|composer.json"
  }
}

resource "coder_script" "auto_dev_server" {
  agent_id           = var.agent_id
  display_name       = "Auto Development Server"
  icon               = "/icon/play.svg"
  script             = templatefile("${path.module}/scripts/auto-dev-server.sh", {
    project_dir        = var.project_dir
    enabled_frameworks = jsonencode(var.enabled_frameworks)
    framework_commands = jsonencode(local.framework_commands)
    detection_patterns = jsonencode(local.detection_patterns)
    start_delay        = var.start_delay
    log_level         = var.log_level
    use_devcontainer  = var.use_devcontainer
  })
  run_on_start       = true
  run_on_stop        = false
  timeout            = 300
}

# Output useful information
output "log_file" {
  description = "Path to the auto-dev-server log file"
  value       = "${var.project_dir}/auto-dev-server.log"
}

output "enabled_frameworks" {
  description = "List of enabled frameworks for detection"
  value       = var.enabled_frameworks
}

output "project_directory" {
  description = "Directory being scanned for projects"
  value       = var.project_dir
}
