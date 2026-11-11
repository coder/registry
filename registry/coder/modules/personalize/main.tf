terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "path" {
  description = "The path to the developer's startup script. Executable files in <path>.d run at start and stop."
  type        = string
  default     = "~/personalize"
  validation {
    condition     = length(regexall("[\n\r]", var.path)) == 0
    error_message = "The personalize path must not contain newlines or carriage returns."
  }
}

resource "coder_script" "personalize" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
    ACTION : "start",
  })
  display_name       = "Personalize"
  icon               = "/icon/personalize.svg"
  log_path           = "$HOME/.coder-modules/coder/personalize/logs/start.log"
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_script" "personalize_stop" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
    ACTION : "stop",
  })
  display_name = "Personalize (stop)"
  icon         = "/icon/personalize.svg"
  log_path     = "$HOME/.coder-modules/coder/personalize/logs/stop.log"
  run_on_stop  = true
}

resource "coder_env" "personalize_path" {
  # The agent expands dollar signs in environment values, but not in scripts.
  count    = can(regex("\\$", var.path)) ? 0 : 1
  agent_id = var.agent_id
  name     = "PERSONALIZE_PATH"
  value    = can(regex("^~/", var.path)) ? "$HOME/${trimprefix(var.path, "~/")}" : var.path
}
