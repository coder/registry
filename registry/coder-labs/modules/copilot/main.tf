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
  description = "Optional project directory. When set, the module pre-creates it if missing and adds it to Copilot's config.json trustedFolders."
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

variable "copilot_settings" {
  type        = string
  description = "Base Copilot user settings as a JSON string, merged into `~/.copilot/settings.json` (banner, theme, model, etc.). Your keys win over existing on-disk keys; unrelated on-disk keys are preserved. Valid theme values: default, github, dim, high-contrast, colorblind."
  default     = ""
}

variable "copilot_config" {
  type        = string
  description = "Base Copilot application config as a JSON string, merged into `~/.copilot/config.json` (for example trustedFolders). workdir is unioned into trustedFolders automatically. Your keys win over existing on-disk keys; unrelated on-disk state such as authentication is preserved."
  default     = ""
}

variable "mcp_config" {
  type        = string
  description = "Custom MCP server configuration as JSON string (in the `{\"mcpServers\": {...}}` shape). Merged into Copilot's `~/.copilot/mcp-config.json`; these servers win over existing entries on duplicate names."
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

variable "enable_ai_gateway" {
  type        = bool
  description = "Route Copilot traffic through AI Gateway Proxy. See https://coder.com/docs/ai-coder/ai-gateway/ai-gateway-proxy"
  default     = false

  validation {
    condition     = !var.enable_ai_gateway || (var.ai_gateway_auth_url != null && length(var.ai_gateway_auth_url) > 0)
    error_message = "ai_gateway_auth_url is required when enable_ai_gateway is true."
  }

  validation {
    condition     = !var.enable_ai_gateway || (var.ai_gateway_cert_path != null && length(var.ai_gateway_cert_path) > 0)
    error_message = "ai_gateway_cert_path is required when enable_ai_gateway is true."
  }
}

variable "ai_gateway_auth_url" {
  type        = string
  description = "AI Gateway Proxy URL with authentication. Use the proxy_auth_url output from the aibridge-proxy module."
  default     = null
  sensitive   = true
}

variable "ai_gateway_cert_path" {
  type        = string
  description = "Path to the AI Gateway Proxy CA certificate. Use the cert_path output from the aibridge-proxy module."
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

# Route Copilot's traffic through the AI Gateway Proxy. The pre-migration module
# scoped these to the Copilot process via its start script; with no start script
# they are set at the agent level, so they apply workspace-wide.
resource "coder_env" "ai_gateway_https_proxy" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "HTTPS_PROXY"
  value    = var.ai_gateway_auth_url
}

resource "coder_env" "ai_gateway_node_extra_ca_certs" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "NODE_EXTRA_CA_CERTS"
  value    = var.ai_gateway_cert_path
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""

  # workdir is trusted automatically; the install script unions it into the
  # trustedFolders array in config.json.
  workdir_trusted_folders = local.workdir != "" ? [local.workdir] : []

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL         = tostring(var.install_copilot)
    ARG_COPILOT_VERSION = var.copilot_version
    ARG_COPILOT_MODEL   = var.copilot_model
    ARG_WORKDIR         = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_SETTINGS_CONFIG = var.copilot_settings != "" ? base64encode(var.copilot_settings) : ""
    ARG_CONFIG_CONFIG   = var.copilot_config != "" ? base64encode(var.copilot_config) : ""
    ARG_TRUSTED_FOLDERS = length(local.workdir_trusted_folders) > 0 ? base64encode(jsonencode(local.workdir_trusted_folders)) : ""
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
