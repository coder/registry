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
  default     = "/icon/kiro.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Kiro CLI."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Kiro CLI."
  default     = null
}

variable "install_kiro_cli" {
  type        = bool
  description = "Whether to install Kiro CLI. When false, a working kiro-cli must already be on PATH."
  default     = true
}

variable "kiro_cli_version" {
  type        = string
  description = "Kiro CLI version to install, for example '2.26.0'. 'latest' with the default kiro_install_url uses the official installer (https://cli.kiro.dev/install); anything else downloads <kiro_install_url>/<version>/kirocli-<arch>-linux.zip. See https://kiro.dev/docs/getting-started/installation/"
  default     = "latest"

  validation {
    condition     = can(regex("^(latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.kiro_cli_version))
    error_message = "kiro_cli_version must be 'latest' or a semantic version such as '2.26.0'."
  }
}

variable "kiro_install_url" {
  type        = string
  description = "Base URL hosting Kiro CLI release archives as <url>/<version>/kirocli-<arch>-linux.zip, for mirrors or air-gapped installs. Defaults to the official stable channel."
  default     = null
}

variable "auth_tarball" {
  type        = string
  description = "Base64 encoded, zstd compressed tarball of a pre-authenticated ~/.local/share/kiro-cli directory. Exported as KIRO_CLI_AUTH_TARBALL and extracted at install time; requires zstd in the workspace."
  default     = ""
  sensitive   = true
}

variable "api_key" {
  type        = string
  description = "Kiro API key, exported as KIRO_API_KEY. Used when no browser login is active; the Kiro docs scope API keys to non-interactive (headless) use. See https://kiro.dev/docs/getting-started/authentication/"
  default     = ""
  sensitive   = true
}

variable "agent_config" {
  type        = string
  description = "Optional custom agent configuration JSON. Written to ~/.kiro/agents/<name>.json and set as chat.defaultAgent. See https://kiro.dev/docs/custom-agents/configuration-reference/"
  default     = null

  validation {
    condition     = var.agent_config == null || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", jsondecode(var.agent_config).name))
    error_message = "agent_config must be a JSON object whose name is a plain file name (letters, digits, '.', '_', '-')."
  }
}

variable "mcp" {
  type        = string
  description = "MCP servers as JSON in Kiro's mcp.json format ({\"mcpServers\": {...}}). Merged into the user-level ~/.kiro/settings/mcp.json; servers already on disk win on duplicate names. See https://kiro.dev/docs/mcp/configuration/"
  default     = ""

  validation {
    condition     = var.mcp == "" || can(jsondecode(var.mcp).mcpServers)
    error_message = "mcp must be a JSON object with an mcpServers key."
  }
}

resource "coder_env" "auth_tarball" {
  count    = var.auth_tarball != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "KIRO_CLI_AUTH_TARBALL"
  value    = var.auth_tarball
}

resource "coder_env" "kiro_api_key" {
  count    = var.api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "KIRO_API_KEY"
  value    = var.api_key
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL      = tostring(var.install_kiro_cli)
    ARG_VERSION      = var.kiro_cli_version
    ARG_INSTALL_URL  = var.kiro_install_url != null ? base64encode(trimsuffix(var.kiro_install_url, "/")) : ""
    ARG_WORKDIR      = local.workdir != "" ? base64encode(local.workdir) : ""
    ARG_AGENT_CONFIG = var.agent_config != null ? base64encode(var.agent_config) : ""
    ARG_MCP_CONFIG   = var.mcp != "" ? base64encode(var.mcp) : ""
  })
  module_dir_name = ".coder-modules/harleylrn/kiro-cli"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Kiro CLI"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
