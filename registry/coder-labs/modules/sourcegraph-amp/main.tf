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
  default     = "/icon/sourcegraph-amp.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing. Amp has no folder trust prompt, so nothing else is written for it."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Amp."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Amp."
  default     = null
}

variable "install_amp" {
  type        = bool
  description = "Whether to install Amp with the official installer. When false, a working amp binary must already be on PATH."
  default     = true
}

variable "amp_version" {
  type        = string
  description = "Amp CLI version to install (for example 0.0.1790769659-g954f35), passed to the official installer as AMP_VERSION. Empty installs the latest release. Amp auto-updates in the background unless amp.updates.mode is \"disabled\". See https://ampcode.com/docs/cli/settings"
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]*$", var.amp_version))
    error_message = "amp_version must be empty or a release version such as 0.0.1790769659-g954f35."
  }
}

variable "amp_api_key" {
  type        = string
  description = "Amp access token, exported as AMP_API_KEY. See https://ampcode.com/docs/cli/execute-mode#non-interactive-environments"
  sensitive   = true
  default     = ""
}

variable "instruction_prompt" {
  type        = string
  description = "Personal guidance written to ~/.config/amp/AGENTS.md, which Amp includes in every session. See https://ampcode.com/docs/customize/agents-md"
  default     = ""
}

variable "amp_settings" {
  type        = string
  description = "Amp user settings as a JSON object of amp.* keys. Merged into ~/.config/amp/settings.json: these keys are overwritten on every start and all other keys are preserved. Use mcp for amp.mcpServers. See https://ampcode.com/docs/cli/settings"
  default     = ""

  validation {
    condition     = var.amp_settings == "" || can(keys(jsondecode(var.amp_settings)))
    error_message = "amp_settings must be a JSON object."
  }

  validation {
    condition     = var.amp_settings == "" || !can(jsondecode(var.amp_settings)["amp.mcpServers"])
    error_message = "amp_settings must not contain amp.mcpServers; use the mcp variable instead."
  }
}

variable "mcp" {
  type        = string
  description = "MCP servers as a JSON object keyed by server name, in the amp.mcpServers format. Merged into ~/.config/amp/settings.json; servers already on disk win on duplicate names, matching amp mcp add. See https://ampcode.com/docs/customize/mcp"
  default     = ""

  validation {
    condition     = var.mcp == "" || can(keys(jsondecode(var.mcp)))
    error_message = "mcp must be a JSON object keyed by server name."
  }
}

variable "managed_settings" {
  type        = any
  description = "Enterprise managed settings written to /etc/ampcode/managed-settings.json. Takes precedence over user and workspace settings. See https://ampcode.com/docs/cli/settings#enterprise-managed-settings"
  default     = null
}

resource "coder_env" "amp_api_key" {
  count    = var.amp_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "AMP_API_KEY"
  value    = var.amp_api_key
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL               = tostring(var.install_amp)
    ARG_AMP_VERSION           = var.amp_version
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_INSTRUCTION_PROMPT    = var.instruction_prompt != "" ? base64encode(var.instruction_prompt) : ""
    ARG_AMP_SETTINGS          = var.amp_settings != "" ? base64encode(var.amp_settings) : ""
    ARG_MCP_CONFIG            = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_MANAGED_SETTINGS_JSON = var.managed_settings != null ? base64encode(jsonencode(var.managed_settings)) : ""
  })
  module_dir_name = ".coder-modules/coder-labs/sourcegraph-amp"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Amp"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
