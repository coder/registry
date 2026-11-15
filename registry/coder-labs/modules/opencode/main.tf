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
  description = "Whether to install OpenCode with the official V2 installer (https://opencode.ai/v2/install). When false, a working OpenCode 2 opencode must already be on PATH."
  default     = true
}

variable "opencode_version" {
  type        = string
  description = "The version of OpenCode to install, for example '2.0.27'. Use 'latest' for the newest release. The module requires OpenCode 2. See https://www.npmjs.com/package/@opencode/cli?activeTab=versions"
  default     = "latest"
}

variable "auth_json" {
  type        = string
  description = "OpenCode credentials in the JSON array format printed by `opencode auth export`. Imported with `opencode auth import`; credentials with the same id are replaced, other saved accounts are preserved. Exported to the workspace as CODER_OPENCODE_AUTH_JSON so it is never rendered into the install script. See https://opencode.ai/v2/docs/cli/providers"
  sensitive   = true
  default     = ""
}

variable "base_opencode_config" {
  type        = string
  description = "OpenCode configuration as JSON. When set, it overwrites the global opencode.json on every start, before mcp is applied. See https://opencode.ai/v2/docs/config/"
  default     = ""
}

variable "mcp" {
  type        = string
  description = "MCP servers as a JSON object keyed by server name, added under mcp.servers in the global opencode.json. Servers already in the file win on duplicate names. See https://opencode.ai/v2/docs/mcp-servers/"
  default     = ""
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
    ARG_INSTALL          = tostring(var.install_opencode)
    ARG_OPENCODE_VERSION = base64encode(var.opencode_version)
    ARG_WORKDIR          = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_BASE_CONFIG      = var.base_opencode_config != "" ? base64encode(var.base_opencode_config) : ""
    ARG_MCP_CONFIG       = var.mcp != "" ? base64encode(var.mcp) : ""
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
