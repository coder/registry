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

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key. Exported as ANTHROPIC_API_KEY."
  default     = ""
  sensitive   = true
}

variable "claude_code_oauth_token" {
  type        = string
  description = "Long-lived Claude.ai subscription token. Generate with `claude setup-token`. Exported as CLAUDE_CODE_OAUTH_TOKEN."
  default     = ""
  sensitive   = true
}

variable "claude_code_version" {
  type        = string
  description = "The version of Claude Code to install. Forwarded to the official installer."
  default     = "latest"
}

variable "install_claude_code" {
  type        = bool
  description = "Whether to install Claude Code via the official installer."
  default     = true
}

variable "claude_binary_path" {
  type        = string
  description = "Directory where the Claude Code binary is located. Use this when Claude is pre-installed outside the module."
  default     = "$HOME/.local/bin"

  validation {
    condition     = var.claude_binary_path == "$HOME/.local/bin" || !var.install_claude_code
    error_message = "Custom claude_binary_path can only be used when install_claude_code is false. The official installer always installs to $HOME/.local/bin and does not support custom paths."
  }
}

variable "disable_autoupdater" {
  type        = bool
  description = "Disable Claude Code automatic updates. Sets DISABLE_AUTOUPDATER=1."
  default     = false
}

variable "model" {
  type        = string
  description = "Default model for Claude Code. Exported as ANTHROPIC_MODEL. Supports aliases (sonnet, opus) or full model names."
  default     = ""
}

variable "claude_md_path" {
  type        = string
  description = "Path to a global CLAUDE.md. Exported as CODER_MCP_CLAUDE_MD_PATH."
  default     = "$HOME/.claude/CLAUDE.md"
}

variable "mcp" {
  type        = string
  description = "Inline MCP JSON (format: {\"mcpServers\": {\"name\": {...}}}). Applied at user scope with `claude mcp add-json --scope user`."
  default     = ""
}

variable "mcp_config_remote_path" {
  type        = list(string)
  description = "List of URLs that return MCP JSON (same shape as `mcp`). Each is fetched and applied at user scope."
  default     = []
}

variable "enable_aibridge" {
  type        = bool
  description = "Route Claude Code through Coder AI Bridge. Sets ANTHROPIC_AUTH_TOKEN and ANTHROPIC_BASE_URL. See https://coder.com/docs/ai-coder/ai-bridge."
  default     = false

  validation {
    condition     = !(var.enable_aibridge && length(var.anthropic_api_key) > 0)
    error_message = "anthropic_api_key cannot be provided when enable_aibridge is true. AI Bridge authenticates using Coder credentials."
  }

  validation {
    condition     = !(var.enable_aibridge && length(var.claude_code_oauth_token) > 0)
    error_message = "claude_code_oauth_token cannot be provided when enable_aibridge is true. AI Bridge authenticates using Coder credentials."
  }
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Claude Code."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Claude Code."
  default     = null
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "anthropic_auth_token" {
  count    = var.enable_aibridge ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "anthropic_base_url" {
  count    = var.enable_aibridge ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_BASE_URL"
  value    = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
}

resource "coder_env" "claude_code_oauth_token" {
  count    = var.claude_code_oauth_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "anthropic_model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_MODEL"
  value    = var.model
}

resource "coder_env" "disable_autoupdater" {
  count    = var.disable_autoupdater ? 1 : 0
  agent_id = var.agent_id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}

resource "coder_env" "claude_code_md_path" {
  count    = var.claude_md_path != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CODER_MCP_CLAUDE_MD_PATH"
  value    = var.claude_md_path
}

locals {
  install_script = file("${path.module}/scripts/install.sh")
}

module "coder-utils" {
  # Pinned to PR #842 branch on coder/registry until coder-utils@1.1.0 is published.
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/coder-utils?ref=feat/coder-utils-optional-install-start"

  agent_id         = var.agent_id
  agent_name       = "claude-code"
  module_directory = "$HOME/.claude-module"

  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_CLAUDE_CODE_VERSION='${var.claude_code_version}' \
    ARG_INSTALL_CLAUDE_CODE='${var.install_claude_code}' \
    ARG_CLAUDE_BINARY_PATH='${var.claude_binary_path}' \
    ARG_MCP='${var.mcp != "" ? base64encode(var.mcp) : ""}' \
    ARG_MCP_CONFIG_REMOTE_PATH='${base64encode(jsonencode(var.mcp_config_remote_path))}' \
    /tmp/install.sh
  EOT
}
