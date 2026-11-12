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
  validation {
    # The agent expands dollar signs in environment values, so the path could
    # not be exported unchanged.
    condition     = length(regexall("[$]", var.path)) == 0
    error_message = "The personalize path must not contain a dollar sign."
  }
}

locals {
  start_log_path = "$HOME/.coder-modules/coder/personalize/logs/start.log"
  stop_log_path  = "$HOME/.coder-modules/coder/personalize/logs/stop.log"

  # The agent expands $HOME in environment values, but not a leading tilde.
  exported_path = (
    can(regex("^~/", var.path))
    ? "$HOME/${trimprefix(var.path, "~/")}"
    : var.path
  )
}

resource "coder_script" "personalize" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
    ACTION : "start",
    LOG_PATH : local.start_log_path,
  })
  display_name       = "Personalize"
  icon               = "/icon/personalize.svg"
  log_path           = local.start_log_path
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_script" "personalize_stop" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
    ACTION : "stop",
    LOG_PATH : local.stop_log_path,
  })
  display_name = "Personalize (stop)"
  icon         = "/icon/personalize.svg"
  log_path     = local.stop_log_path
  run_on_stop  = true
}

# These variables tell the developer's own tooling, such as a dotfiles install
# script, where this template's Personalize looks for scripts.
resource "coder_env" "path" {
  agent_id = var.agent_id
  name     = "CODER_MODULE_PERSONALIZE_PATH"
  value    = local.exported_path
}

resource "coder_env" "dir" {
  agent_id = var.agent_id
  name     = "CODER_MODULE_PERSONALIZE_DIR"
  value    = "${local.exported_path}.d"
}
