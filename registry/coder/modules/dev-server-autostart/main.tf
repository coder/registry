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

variable "work_dir" {
  type        = string
  description = "Directory to scan for projects. Defaults to agent directory or /workspaces."
  default     = ""
}

variable "scan_subdirectories" {
  type        = bool
  description = "Whether to scan subdirectories for projects."
  default     = true
}

variable "max_depth" {
  type        = number
  description = "Maximum directory depth to scan for projects."
  default     = 2
  validation {
    condition     = var.max_depth >= 1 && var.max_depth <= 10
    error_message = "max_depth must be between 1 and 10."
  }
}

variable "custom_commands" {
  type        = map(string)
  description = "Override default commands for specific project types (e.g., {\"node\" = \"npm run dev\", \"python\" = \"uvicorn main:app --reload\"})."
  default     = {}
}

variable "devcontainer_integration" {
  type        = bool
  description = "Enable devcontainer.json integration for postCreateCommand, postStartCommand, etc."
  default     = true
}

variable "devcontainer_service" {
  type        = string
  description = "Specific service to start from docker-compose.yml (when using devcontainer with docker-compose)."
  default     = ""
}

variable "disabled_frameworks" {
  type        = list(string)
  description = "List of frameworks to ignore during detection (e.g., [\"php\", \"java\"])."
  default     = []
}

variable "startup_delay" {
  type        = number
  description = "Delay in seconds before starting servers to allow workspace to fully initialize."
  default     = 5
  validation {
    condition     = var.startup_delay >= 0 && var.startup_delay <= 60
    error_message = "startup_delay must be between 0 and 60 seconds."
  }
}

variable "health_check_enabled" {
  type        = bool
  description = "Enable basic health checks for started servers."
  default     = true
}

variable "log_level" {
  type        = string
  description = "Logging level for the auto-start script."
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warn, error."
  }
}

variable "auto_install_deps" {
  type        = bool
  description = "Automatically install dependencies if detected (npm install, pip install, etc.)."
  default     = true
}

variable "timeout_seconds" {
  type        = number
  description = "Timeout in seconds for dependency installation and server startup."
  default     = 300
  validation {
    condition     = var.timeout_seconds >= 30 && var.timeout_seconds <= 1800
    error_message = "timeout_seconds must be between 30 and 1800 seconds."
  }
}

locals {
  # Determine working directory - prioritize user input, fall back to common paths
  working_directory = var.work_dir != "" ? var.work_dir : (
    # Check if /workspaces exists (common in devcontainers)
    "/workspaces"
  )

  # Convert disabled frameworks to a string for shell script
  disabled_frameworks_str = join(",", var.disabled_frameworks)

  # Convert custom commands to shell-compatible format
  custom_commands_str = join("\n", [
    for key, value in var.custom_commands :
    "CUSTOM_CMD_${upper(key)}='${value}'"
  ])

  # Script environment variables
  script_env = {
    WORK_DIR                    = local.working_directory
    SCAN_SUBDIRECTORIES        = var.scan_subdirectories ? "true" : "false"
    MAX_DEPTH                  = tostring(var.max_depth)
    DEVCONTAINER_INTEGRATION   = var.devcontainer_integration ? "true" : "false"
    DEVCONTAINER_SERVICE       = var.devcontainer_service
    DISABLED_FRAMEWORKS        = local.disabled_frameworks_str
    STARTUP_DELAY              = tostring(var.startup_delay)
    HEALTH_CHECK_ENABLED       = var.health_check_enabled ? "true" : "false"
    LOG_LEVEL                  = var.log_level
    AUTO_INSTALL_DEPS          = var.auto_install_deps ? "true" : "false"
    TIMEOUT_SECONDS            = tostring(var.timeout_seconds)
  }
}

# Run the dev server auto-start script
resource "coder_script" "dev_server_autostart" {
  agent_id     = var.agent_id
  display_name = "Development Server Auto-Start"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    custom_commands = local.custom_commands_str
  })
  
  # Set environment variables for the script
  dynamic "env" {
    for_each = local.script_env
    content {
      name  = env.key
      value = env.value
    }
  }

  run_on_start = true
  run_on_stop  = false
  timeout      = var.timeout_seconds
}

# Output information about detected servers (for debugging)
output "script_output" {
  description = "Information about the dev server auto-start script execution."
  value = {
    agent_id          = var.agent_id
    working_directory = local.working_directory
    script_id         = coder_script.dev_server_autostart.id
    environment_vars  = local.script_env
  }
}
