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

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/claude.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and pre-accepts the Claude Code trust/onboarding prompt for it in ~/.claude.json."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Claude Code. Can be used for dependency ordering between modules (e.g., waiting for git-clone to complete before Claude Code initialization)."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Claude Code."
  default     = null
}

variable "install_claude_code" {
  type        = bool
  description = "Whether to install Claude Code."
  default     = true
}

variable "claude_code_version" {
  type        = string
  description = "The version of Claude Code to install."
  default     = "latest"
}

variable "disable_autoupdater" {
  type        = bool
  description = "Disable Claude Code automatic updates. When true, Claude Code will stay on the installed version."
  default     = false
}

variable "anthropic_api_key" {
  type        = string
  description = "API key passed to Claude Code via the ANTHROPIC_API_KEY env var. Prefer api_key_helper for short-lived credentials."
  sensitive   = true
  default     = ""
}

variable "model" {
  type        = string
  description = "Sets the default model for Claude Code via ANTHROPIC_MODEL env var. If empty, Claude Code uses its default. Supports aliases (sonnet, opus) or full model names."
  default     = ""
}

variable "mcp" {
  type        = string
  description = "JSON-encoded string of MCP server configurations. When set, servers are added at Claude Code's user scope so they are available across every project the workspace owner opens."
  default     = ""
}

variable "mcp_config_remote_path" {
  type        = list(string)
  description = "List of URLs that return JSON MCP server configurations (text/plain with valid JSON). Servers are added at Claude Code's user scope."
  default     = []
}

variable "claude_code_oauth_token" {
  type        = string
  description = "OAuth token passed to Claude Code via the CLAUDE_CODE_OAUTH_TOKEN env var. Generate one with `claude setup-token`."
  sensitive   = true
  default     = ""
}

variable "claude_binary_path" {
  type        = string
  description = "Directory where the Claude Code binary is located. Use this if Claude is pre-installed or installed outside the module to a non-default location."
  default     = "$HOME/.local/bin"

  validation {
    condition     = var.claude_binary_path == "$HOME/.local/bin" || !var.install_claude_code
    error_message = "Custom claude_binary_path can only be used when install_claude_code is false. The official installer always installs to $HOME/.local/bin and does not support custom paths."
  }
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Use AI Gateway for Claude Code. https://coder.com/docs/ai-coder/ai-gateway"
  default     = false

  validation {
    condition     = !(var.enable_ai_gateway && length(var.anthropic_api_key) > 0)
    error_message = "anthropic_api_key cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates the client using Coder credentials."
  }

  validation {
    condition     = !(var.enable_ai_gateway && length(var.claude_code_oauth_token) > 0)
    error_message = "claude_code_oauth_token cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates the client using Coder credentials."
  }
}

variable "api_key_helper" {
  type = object({
    script = string
    ttl_ms = optional(number, 300000)
  })
  description = "Script that prints an Anthropic API key to stdout. Written to ~/.claude/coder-api-key-helper.sh and registered via the apiKeyHelper setting in /etc/claude-code/managed-settings.d/. Use for short-lived credentials from Vault, AWS Secrets Manager, cloud IAM, etc. ttl_ms is how long Claude Code caches each key (default 5 minutes)."
  default     = null

  validation {
    condition     = var.api_key_helper == null || (var.anthropic_api_key == "" && var.claude_code_oauth_token == "")
    error_message = "api_key_helper cannot be combined with anthropic_api_key or claude_code_oauth_token. Use exactly one authentication method."
  }

  validation {
    condition     = var.api_key_helper == null || !var.enable_ai_gateway
    error_message = "api_key_helper cannot be combined with enable_ai_gateway. AI Gateway authenticates using the workspace owner's session token."
  }
}

resource "coder_env" "claude_code_oauth_token" {
  count    = var.claude_code_oauth_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

# ANTHROPIC_AUTH_TOKEN authenticates the client against Coder's AI Gateway
# using the workspace owner's session token, per the AI Gateway docs.
resource "coder_env" "anthropic_auth_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "disable_autoupdater" {
  count    = var.disable_autoupdater ? 1 : 0
  agent_id = var.agent_id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}


resource "coder_env" "anthropic_model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_MODEL"
  value    = var.model
}

resource "coder_env" "anthropic_base_url" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

resource "coder_env" "api_key_helper_ttl" {
  count    = var.api_key_helper != null ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_API_KEY_HELPER_TTL_MS"
  value    = tostring(var.api_key_helper.ttl_ms)
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_CLAUDE_CODE_VERSION    = var.claude_code_version
    ARG_INSTALL_CLAUDE_CODE    = tostring(var.install_claude_code)
    ARG_CLAUDE_BINARY_PATH     = var.claude_binary_path
    ARG_WORKDIR                = local.workdir
    ARG_MCP                    = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_MCP_CONFIG_REMOTE_PATH = base64encode(jsonencode(var.mcp_config_remote_path))
    ARG_ENABLE_AI_GATEWAY      = tostring(var.enable_ai_gateway)
    ARG_API_KEY_HELPER_SCRIPT  = var.api_key_helper != null ? base64encode(var.api_key_helper.script) : ""
  })
  module_dir_name = ".coder-modules/coder/claude-code"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Claude Code"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

# Pass-through of coder-utils script outputs so upstream modules can serialize
# their coder_script resources behind this module's install pipeline using
# `coder exp sync want <self> <each name>`.
output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
