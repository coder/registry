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

# Variable to define which JetBrains plugins to install
variable "plugins" {
  type        = list(string)
  description = "A list of JetBrains plugin IDs to pre-install (e.g. ['org.rust.lang', 'com.github.copilot'])."
  default     = []
}

variable "log_path" {
  type        = string
  description = "The path to the module log file."
  default     = "/tmp/jetbrains_plugins.log"
}

variable "port" {
  type        = number
  description = "The port to run the IDE application on."
  default     = 19999
}

# Resource to execute the plugin installation script on the agent
resource "coder_script" "jetbrains_plugins" {
  agent_id     = var.agent_id
  display_name = "JetBrains Plugin Pre-installer"
  icon         = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/jetbrains.svg"
  
  # Injecting variables into the bash script using templatefile
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PLUGINS  : join(" ", var.plugins)
  })
  
  run_on_start = true
}

# Coder app definition for the JetBrains IDE
resource "coder_app" "jetbrains_app" {
  agent_id     = var.agent_id
  slug         = "jetbrains-ide"
  display_name = "JetBrains IDE"
  url          = "http://localhost:${var.port}"
  icon         = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/jetbrains.svg"
}