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
  default     = "/icon/auggie.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
}

variable "install_auggie" {
  type        = bool
  description = "Whether to install Auggie CLI with npm. When false, a working auggie must already be on PATH."
  default     = true
}

variable "auggie_version" {
  type        = string
  description = "The version of Auggie CLI to install. Empty installs the latest version."
  default     = ""
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Auggie."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Auggie."
  default     = null
}

variable "mcp" {
  type        = string
  description = "MCP servers as a JSON string ({\"mcpServers\": {...}}), added to ~/.augment/settings.json with `auggie mcp add-json`. Servers already configured win on duplicate names. See https://docs.augmentcode.com/cli/integrations#mcp-integrations"
  default     = ""
}

variable "mcp_files" {
  type        = list(string)
  description = "Paths to MCP configuration JSON files in the workspace, added the same way as mcp. See https://docs.augmentcode.com/cli/integrations#mcp-integrations"
  default     = []
}

variable "rules" {
  type        = string
  description = "Rules in markdown, written to ~/.augment/rules/coder-module.md so they apply to every Auggie session. See https://docs.augmentcode.com/cli/rules"
  default     = ""
}

variable "augment_session_token" {
  type        = string
  description = "Augment session JSON from `auggie token print`, exported as AUGMENT_SESSION_AUTH. See https://docs.augmentcode.com/cli/setup-auggie/authentication"
  sensitive   = true
  default     = ""
}

variable "auggie_model" {
  type        = string
  description = "Default model, written to the model key of ~/.augment/settings.json. Find available models with `auggie models list`."
  default     = ""
}

resource "coder_env" "auggie_session_auth" {
  count    = var.augment_session_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "AUGMENT_SESSION_AUTH"
  value    = var.augment_session_token
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL        = tostring(var.install_auggie)
    ARG_AUGGIE_VERSION = var.auggie_version != "" ? base64encode(var.auggie_version) : ""
    ARG_WORKDIR        = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_MCP_CONFIG     = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_MCP_FILES      = length(var.mcp_files) > 0 ? base64encode(jsonencode(var.mcp_files)) : ""
    ARG_RULES          = var.rules != "" ? base64encode(var.rules) : ""
    ARG_AUGGIE_MODEL   = var.auggie_model != "" ? base64encode(var.auggie_model) : ""
  })
  module_dir_name = ".coder-modules/coder-labs/auggie"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Auggie"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
