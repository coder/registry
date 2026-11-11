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
    condition = (
      trimspace(var.path) != ""
      && var.path != "~"
      && !can(regex("/$", var.path))
      && !can(regex("(^|/)\\.\\.?$", var.path))
      && length(regexall("[\n\r]", var.path)) == 0
    )
    error_message = "The personalize path must not be empty or whitespace-only, be only ~, end with /, have . or .. as its last component, or contain newlines or carriage returns."
  }
}

resource "coder_script" "personalize" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
  })
  display_name       = "Personalize"
  icon               = "/icon/personalize.svg"
  log_path           = "$HOME/.coder-modules/coder/personalize/logs/start.log"
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_script" "personalize_stop" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/stop.sh", {
    PERSONALIZE_PATH : base64encode(var.path),
  })
  display_name = "Personalize (stop)"
  icon         = "/icon/personalize.svg"
  log_path     = "$HOME/.coder-modules/coder/personalize/logs/stop.log"
  run_on_stop  = true
}

locals {
  # Relative paths are resolved when the script runs, so only absolute and ~/
  # paths are exported. The agent expands dollar signs in environment values,
  # but not in scripts, so a path with a dollar sign is not exported either.
  path_is_absolute_or_under_home = can(regex("^(/|~/)", var.path))
  path_has_dollar_sign           = can(regex("\\$", var.path))
  export_path                    = local.path_is_absolute_or_under_home && !local.path_has_dollar_sign

  # A leading ~/ becomes $HOME/, which the agent expands.
  exported_path = (
    can(regex("^~/", var.path))
    ? "$HOME/${trimprefix(var.path, "~/")}"
    : var.path
  )
}

resource "coder_env" "personalize_path" {
  count    = local.export_path ? 1 : 0
  agent_id = var.agent_id
  name     = "PERSONALIZE_PATH"
  value    = local.exported_path
}
