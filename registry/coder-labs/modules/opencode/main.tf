terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "icon" {
  type        = string
  description = "The icon to use for the install scripts."
  default     = "/icon/opencode.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing. OpenCode has no workspace trust prompt, so nothing else is written for it."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing OpenCode."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing OpenCode."
  default     = null
}

variable "install_opencode" {
  type        = bool
  description = "Whether to install OpenCode with the official installer (https://opencode.ai/install). When false, a working opencode must already be on PATH."
  default     = true
}

variable "opencode_version" {
  type        = string
  description = "The version of OpenCode to install, for example '1.18.33'. Use 'latest' for the newest release. See https://github.com/anomalyco/opencode/releases"
  default     = "latest"

  validation {
    condition     = can(regex("^(latest|v?[0-9]+\\.[0-9]+\\.[0-9]+[0-9A-Za-z.+-]*)$", var.opencode_version))
    error_message = "opencode_version must be 'latest' or a release version such as '1.18.33'."
  }
}

variable "auth_json" {
  type        = string
  description = "OpenCode credentials in the format of $HOME/.local/share/opencode/auth.json. Merged into that file (module-provided providers win, other providers are preserved). Exported to the workspace as CODER_OPENCODE_AUTH_JSON so it is never rendered into the install script. See https://opencode.ai/docs/providers/#credentials"
  sensitive   = true
  default     = ""

  validation {
    condition     = var.auth_json == "" || can(keys(jsondecode(var.auth_json)))
    error_message = "auth_json must be a JSON object keyed by provider ID."
  }
}

variable "config_json" {
  type        = string
  description = "OpenCode config as JSON, deep-merged into the global $HOME/.config/opencode/opencode.json. Keys set here win; other keys on disk are preserved. Configure MCP servers with the mcp variable instead. See https://opencode.ai/docs/config/"
  default     = ""

  validation {
    condition     = var.config_json == "" || can(keys(jsondecode(var.config_json)))
    error_message = "config_json must be a JSON object."
  }

  validation {
    condition     = var.config_json == "" || !can(jsondecode(var.config_json).mcp)
    error_message = "config_json must not contain an mcp key; use the mcp variable for MCP servers."
  }
}

variable "mcp" {
  type        = string
  description = "MCP servers as a JSON object keyed by server name, in the format of the mcp key of opencode.json. Merged into $HOME/.config/opencode/opencode.json; servers already on disk win on duplicate names. See https://opencode.ai/docs/mcp-servers/"
  default     = ""

  validation {
    condition     = var.mcp == "" || can(keys(jsondecode(var.mcp)))
    error_message = "mcp must be a JSON object keyed by MCP server name."
  }
}

variable "managed_settings" {
  type        = any
  description = "OpenCode config written as root to /etc/opencode/opencode.json. Managed config has the highest precedence and cannot be overridden by user or project config. See https://opencode.ai/docs/config/#managed-settings"
  default     = null

  validation {
    condition     = var.managed_settings == null || can(keys(var.managed_settings))
    error_message = "managed_settings must be an object."
  }
}

resource "coder_env" "opencode_auth_json" {
  count    = var.auth_json != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CODER_OPENCODE_AUTH_JSON"
  value    = var.auth_json
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL               = tostring(var.install_opencode)
    ARG_OPENCODE_VERSION      = var.opencode_version
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_CONFIG_JSON           = var.config_json != "" ? base64encode(var.config_json) : ""
    ARG_MCP_CONFIG            = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_MANAGED_SETTINGS_JSON = var.managed_settings != null ? base64encode(jsonencode(var.managed_settings)) : ""
  })
  module_dir_name = ".coder-modules/coder-labs/opencode"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "OpenCode"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
