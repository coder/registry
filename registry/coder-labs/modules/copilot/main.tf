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
  description = "The icon to use for the app."
  default     = "/icon/github.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and adds it as a trusted folder in Copilot's config.json."
  default     = null
}

variable "github_token" {
  type        = string
  description = "GitHub OAuth token or Personal Access Token. When set, exported to the workspace as GITHUB_TOKEN and GH_TOKEN."
  default     = ""
  sensitive   = true
}

variable "copilot_model" {
  type        = string
  description = "The model to use for Copilot. Any model supported by GitHub Copilot can be used."
  default     = "claude-sonnet-4.5"
}

variable "copilot_config" {
  type        = string
  description = "Custom Copilot configuration as JSON string. Leave empty to use default configuration with banner disabled, theme set to auto, and workdir as trusted folder."
  default     = ""
}

variable "trusted_directories" {
  type        = list(string)
  description = "Additional directories to trust for Copilot operations. Written to Copilot's config.json trusted_folders."
  default     = []
}

variable "mcp_config" {
  type        = string
  description = "Custom MCP server configuration as JSON string (in the `{\"mcpServers\": {...}}` shape). Merged into Copilot's `~/.copilot/mcp-config.json`; existing entries win on duplicate server names."
  default     = ""
}

variable "copilot_version" {
  type        = string
  description = "The version of GitHub Copilot CLI to install. Use 'latest' for the latest version or specify a version like '0.0.334'."
  default     = "latest"
}

variable "install_copilot" {
  type        = bool
  description = "Whether to install GitHub Copilot CLI."
  default     = true
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Copilot."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Copilot."
  default     = null
}

resource "coder_env" "copilot_model" {
  count    = var.copilot_model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "COPILOT_MODEL"
  value    = var.copilot_model
}

resource "coder_env" "github_token" {
  count    = var.github_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GITHUB_TOKEN"
  value    = var.github_token
}

resource "coder_env" "gh_token" {
  count    = var.github_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GH_TOKEN"
  value    = var.github_token
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""

  all_trusted_folders = concat(local.workdir != "" ? [local.workdir] : [], var.trusted_directories)

  parsed_custom_config = try(jsondecode(var.copilot_config), {})

  existing_trusted_folders = try(local.parsed_custom_config.trusted_folders, [])

  merged_copilot_config = merge(
    {
      banner = "never"
      theme  = "auto"
    },
    local.parsed_custom_config,
    {
      trusted_folders = concat(local.existing_trusted_folders, local.all_trusted_folders)
    }
  )

  final_copilot_config = jsonencode(local.merged_copilot_config)

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL         = tostring(var.install_copilot)
    ARG_COPILOT_VERSION = var.copilot_version
    ARG_COPILOT_MODEL   = var.copilot_model
    ARG_WORKDIR         = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_COPILOT_CONFIG  = base64encode(local.final_copilot_config)
    ARG_MCP_CONFIG      = var.mcp_config != "" ? base64encode(var.mcp_config) : ""
  })

  module_dir_name = ".coder-modules/coder-labs/copilot"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Copilot"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
