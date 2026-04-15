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

variable "master_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Human 1ck_ API key for Terraform-native provisioning. Creates vault + agent at terraform apply; cleans up at terraform destroy. Credentials are available as outputs immediately — no shell bootstrap needed."
}

variable "token_ttl_hours" {
  type        = number
  default     = 8
  description = "TTL in hours for the agent's scoped JWT (Terraform-native mode). Set to 0 for the platform default (1 hour)."

  validation {
    condition     = var.token_ttl_hours >= 0 && var.token_ttl_hours <= 720
    error_message = "token_ttl_hours must be between 0 and 720 (30 days)."
  }
}

variable "auto_destroy_vault" {
  type        = bool
  default     = false
  description = "Whether to delete the provisioned vault on terraform destroy. When false (default), only the agent is deleted."
}

variable "provision_vault_name" {
  type        = string
  default     = ""
  description = "Vault name for Terraform-native provisioning. Defaults to coder-<workspace_name>."
}

variable "provision_agent_name" {
  type        = string
  default     = ""
  description = "Agent name for Terraform-native provisioning. Defaults to coder-<workspace_name>-agent."
}

variable "provision_policy_path" {
  type        = string
  default     = "**"
  description = "Secret path pattern for the auto-created access policy (Terraform-native mode)."
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
