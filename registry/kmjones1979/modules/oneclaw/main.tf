terraform {
  required_version = ">= 1.4"

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

variable "vault_id" {
  type        = string
  description = "The 1Claw vault ID to scope MCP access to. Optional when using bootstrap mode (human_api_key)."
  default     = ""

  validation {
    condition     = var.vault_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.vault_id))
    error_message = "vault_id must be a valid UUID or empty (for bootstrap mode)."
  }
}

variable "api_token" {
  type        = string
  sensitive   = true
  description = "1Claw agent API key (starts with ocv_). Optional when using bootstrap mode (human_api_key)."
  default     = ""
}

variable "human_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "One-time human 1ck_ API key for auto-provisioning. On first workspace start, creates a vault, agent, and policy automatically. Credentials are cached in ~/.1claw/bootstrap.json for subsequent starts."
}

variable "bootstrap_vault_name" {
  type        = string
  default     = "coder-workspace"
  description = "Name for the auto-created vault (only used when vault_id is not provided and human_api_key is set)."
}

variable "bootstrap_agent_name" {
  type        = string
  default     = ""
  description = "Name for the auto-created agent. Defaults to coder-<workspace_name>."
}

variable "bootstrap_policy_path" {
  type        = string
  default     = "**"
  description = "Secret path pattern for the auto-created policy (glob). Defaults to all secrets."
}

variable "agent_id_1claw" {
  type        = string
  description = "Optional 1Claw agent UUID. When omitted, the MCP server resolves the agent from the API key prefix."
  default     = ""
}

variable "mcp_host" {
  type        = string
  description = "Base URL of the 1Claw MCP server."
  default     = "https://mcp.1claw.xyz/mcp"

  validation {
    condition     = can(regex("^https?://", var.mcp_host))
    error_message = "mcp_host must start with http:// or https://."
  }
}

variable "base_url" {
  type        = string
  description = "Base URL of the 1Claw Vault API (used by ONECLAW_BASE_URL env var)."
  default     = "https://api.1claw.xyz"

  validation {
    condition     = can(regex("^https?://", var.base_url))
    error_message = "base_url must start with http:// or https://."
  }
}

variable "install_cursor_config" {
  type        = bool
  description = "Whether to write MCP config to the Cursor IDE config path."
  default     = true
}

variable "install_claude_config" {
  type        = bool
  description = "Whether to write MCP config to the Claude Code config path."
  default     = true
}

variable "cursor_config_path" {
  type        = string
  description = "Path where the Cursor MCP config file is written."
  default     = "$HOME/.cursor/mcp.json"
}

variable "claude_config_path" {
  type        = string
  description = "Path where the Claude Code MCP config file is written."
  default     = "$HOME/.config/claude/mcp.json"
}

variable "icon" {
  type        = string
  description = "Icon to display for the setup script in the Coder UI."
  default     = "/icon/vault.svg"
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
  default     = null
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  bootstrap_mode = var.human_api_key != ""
  bootstrap_agent_name = (
    var.bootstrap_agent_name != "" ? var.bootstrap_agent_name :
    "coder-${data.coder_workspace.me.name}"
  )
}

resource "coder_env" "vault_id" {
  count    = var.vault_id != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_VAULT_ID"
  value    = var.vault_id
}

resource "coder_env" "agent_api_key" {
  count    = var.api_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_AGENT_API_KEY"
  value    = var.api_token
}

resource "coder_env" "oneclaw_agent_id" {
  count    = var.agent_id_1claw != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_AGENT_ID"
  value    = var.agent_id_1claw
}

resource "coder_env" "base_url" {
  agent_id = var.agent_id
  name     = "ONECLAW_BASE_URL"
  value    = var.base_url
}

# Sensitive values are passed via coder_env (not templated into the script body)
# so they don't appear in the Coder agent's script log. The agent log is 0600 on
# the coder user, but that's the same user the AI runs as in most images, so we
# want to avoid any on-disk copy of the 1ck_ key in the workspace.
resource "coder_env" "human_api_key" {
  count    = local.bootstrap_mode ? 1 : 0
  agent_id = var.agent_id
  name     = "_ONECLAW_HUMAN_API_KEY"
  value    = var.human_api_key
}

resource "coder_script" "run" {
  agent_id           = var.agent_id
  display_name       = "1Claw"
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = local.bootstrap_mode

  script = templatefile("${path.module}/scripts/run.sh", {
    BOOTSTRAP_MODE        = local.bootstrap_mode ? "true" : "false"
    BASE_URL              = var.base_url
    VAULT_ID_INPUT        = var.vault_id
    VAULT_NAME            = var.bootstrap_vault_name
    AGENT_NAME            = local.bootstrap_agent_name
    POLICY_PATH           = var.bootstrap_policy_path
    STATE_DIR             = "$HOME/.1claw"
    MCP_HOST              = var.mcp_host
    INSTALL_CURSOR_CONFIG = var.install_cursor_config ? "true" : "false"
    INSTALL_CLAUDE_CONFIG = var.install_claude_config ? "true" : "false"
    CURSOR_CONFIG_PATH    = var.cursor_config_path
    CLAUDE_CONFIG_PATH    = var.claude_config_path
  })
}

output "mcp_config_path" {
  description = "Primary MCP config file path (Cursor). Use this to reference the config from downstream resources."
  value       = var.cursor_config_path
}

output "claude_config_path" {
  description = "Claude Code MCP config file path."
  value       = var.install_claude_config ? var.claude_config_path : ""
}

output "vault_id" {
  description = "The 1Claw vault ID configured for this workspace (manual mode only; bootstrap mode resolves the vault ID inside the workspace)."
  value       = var.vault_id
  sensitive   = true
}

output "agent_id_1claw" {
  description = "The 1Claw agent UUID, if provided via variable."
  value       = var.agent_id_1claw
  sensitive   = true
}

output "provisioning_mode" {
  description = "Which provisioning mode is active: bootstrap or manual."
  value       = local.bootstrap_mode ? "bootstrap" : "manual"
  sensitive   = true
}
