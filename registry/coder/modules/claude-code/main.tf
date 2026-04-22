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

variable "anthropic_api_key" {
  type        = string
  description = "Convenience shortcut for setting ANTHROPIC_API_KEY. Equivalent to adding ANTHROPIC_API_KEY to `env`."
  default     = ""
  sensitive   = true
}

variable "claude_code_oauth_token" {
  type        = string
  description = "Convenience shortcut for setting CLAUDE_CODE_OAUTH_TOKEN. Generate with `claude setup-token`. Equivalent to adding CLAUDE_CODE_OAUTH_TOKEN to `env`."
  default     = ""
  sensitive   = true
}

variable "env" {
  type        = map(string)
  description = "Arbitrary environment variables to export to the Coder agent. Each key/value pair becomes a `coder_env` resource. Use this for any Claude Code env var (ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, CLAUDE_CODE_USE_BEDROCK, etc.) or for custom vars your pre/post scripts consume."
  default     = {}

  validation {
    condition     = !contains(keys(var.env), "ANTHROPIC_API_KEY")
    error_message = "Use the `anthropic_api_key` variable instead of setting ANTHROPIC_API_KEY via `env`. It is marked sensitive and handled as a dedicated resource."
  }

  validation {
    condition     = !contains(keys(var.env), "CLAUDE_CODE_OAUTH_TOKEN")
    error_message = "Use the `claude_code_oauth_token` variable instead of setting CLAUDE_CODE_OAUTH_TOKEN via `env`. It is marked sensitive and handled as a dedicated resource."
  }
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

locals {
  # `env` fans out to one `coder_env` per entry via for_each. Sensitive
  # shortcuts (anthropic_api_key, claude_code_oauth_token) can't be merged in
  # because Terraform forbids sensitive values as for_each keys. They're
  # emitted as dedicated resources below instead.
  install_script = file("${path.module}/scripts/install.sh")
}

resource "coder_env" "env" {
  for_each = var.env
  agent_id = var.agent_id
  name     = each.key
  value    = each.value
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "claude_code_oauth_token" {
  count    = var.claude_code_oauth_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
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
