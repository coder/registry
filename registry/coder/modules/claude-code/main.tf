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

variable "env" {
  type        = map(string)
  description = "Environment variables to export to the Coder agent. Each key/value pair becomes one coder_env resource. Use this for any Claude Code env var (ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_BASE_URL, ANTHROPIC_MODEL, CLAUDE_CODE_USE_BEDROCK, etc.) or for custom vars your pre/post scripts consume. Declare your Terraform variable with `sensitive = true` to keep secrets out of plan output."
  default     = {}
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
  # Prepend ARG_* exports pulled from Terraform variables directly in front of
  # the install script body. coder-utils then takes the combined string,
  # writes it to $HOME/.claude-module/install.sh, and runs it. One file on
  # disk, one base64 round-trip, no /tmp wrapper.
  install_script = join("\n", [
    "#!/bin/bash",
    "set -euo pipefail",
    "",
    "export ARG_CLAUDE_CODE_VERSION='${var.claude_code_version}'",
    "export ARG_INSTALL_CLAUDE_CODE='${var.install_claude_code}'",
    "export ARG_CLAUDE_BINARY_PATH='${var.claude_binary_path}'",
    "export ARG_MCP='${var.mcp != "" ? base64encode(var.mcp) : ""}'",
    "export ARG_MCP_CONFIG_REMOTE_PATH='${base64encode(jsonencode(var.mcp_config_remote_path))}'",
    "",
    file("${path.module}/scripts/install.sh"),
  ])
}

# Fan var.env out into one coder_env per entry. Keys are lifted out of
# their sensitivity taint with `nonsensitive` so Terraform can use them as
# for_each instance addresses; values retain any sensitivity attached by
# the caller's variable declaration.
resource "coder_env" "env" {
  for_each = nonsensitive(toset(keys(var.env)))
  agent_id = var.agent_id
  name     = each.key
  value    = var.env[each.key]
}

module "coder-utils" {
  # Pinned to PR #842 branch on coder/registry until coder-utils@1.1.0 is published.
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/coder-utils?ref=feat/coder-utils-optional-install-start"

  agent_id         = var.agent_id
  agent_name       = "claude-code"
  module_directory = "$HOME/.claude-module"

  display_name_prefix = "Claude Code"
  icon                = "/icon/claude.svg"

  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script

  install_script = local.install_script
}
