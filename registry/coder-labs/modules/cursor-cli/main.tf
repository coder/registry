terraform {
  required_version = ">= 1.9"

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
  default     = "/icon/cursor.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and marks it as a trusted workspace for Cursor CLI, equivalent to accepting the trust prompt or passing --trust."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Cursor CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Cursor CLI."
  default     = null
}

variable "install_cursor_cli" {
  type        = bool
  description = "Whether to install Cursor CLI with the official installer. When false, a working cursor-agent must already be on PATH."
  default     = true
}

variable "api_key" {
  type        = string
  description = "Cursor API key, exported as CURSOR_API_KEY. See https://cursor.com/docs/cli/reference/authentication"
  sensitive   = true
  default     = ""
}

variable "cursor_config_dir" {
  type        = string
  description = "Directory for Cursor CLI's cli-config.json, exported as CURSOR_CONFIG_DIR. Empty (default) leaves CURSOR_CONFIG_DIR unset so an existing value or the default ~/.cursor is used. Does not move mcp.json, which Cursor CLI always reads from ~/.cursor. See https://cursor.com/docs/cli/reference/configuration"
  default     = ""
}

variable "mcp" {
  type        = string
  description = "MCP servers as JSON in Cursor's mcp.json format ({\"mcpServers\": {...}}). Merged into the user-level ~/.cursor/mcp.json; servers already on disk win on duplicate names. See https://cursor.com/docs/cli/mcp"
  default     = ""

  validation {
    condition     = var.mcp == "" || can(jsondecode(var.mcp).mcpServers)
    error_message = "mcp must be a JSON object with an mcpServers key."
  }
}

variable "rules_files" {
  type        = map(string)
  description = "Optional map of rule file name to content, written to <workdir>/.cursor/rules/<name>. Requires workdir. See https://cursor.com/docs/context/rules"
  default     = {}

  validation {
    condition     = length(var.rules_files) == 0 || (var.workdir != null && var.workdir != "")
    error_message = "rules_files requires workdir to be set."
  }

  validation {
    condition     = alltrue([for name in keys(var.rules_files) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", name))])
    error_message = "rules_files names must be plain file names (letters, digits, '.', '_', '-') without path separators."
  }
}

resource "coder_env" "cursor_api_key" {
  count    = var.api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CURSOR_API_KEY"
  value    = var.api_key
}

resource "coder_env" "cursor_config_dir" {
  count    = var.cursor_config_dir != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CURSOR_CONFIG_DIR"
  value    = var.cursor_config_dir
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL     = tostring(var.install_cursor_cli)
    ARG_WORKDIR     = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_MCP_CONFIG  = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_RULES_FILES = length(var.rules_files) > 0 ? base64encode(jsonencode(var.rules_files)) : ""
  })
  module_dir_name = ".coder-modules/coder-labs/cursor-cli"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Cursor CLI"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
