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
  description = "Environment variables to export to the workspace. Use this for any Claude Code env var (ANTHROPIC_API_KEY, ANTHROPIC_BASE_URL, CLAUDE_CODE_USE_BEDROCK, etc.) or for custom vars your pre/post scripts consume. Keys that are also wired by a convenience input (model, claude_code_oauth_token, enable_ai_gateway, disable_auto_updater) fail at plan time; use one or the other."
  default     = {}

  validation {
    condition     = var.model == "" || !contains(keys(var.env), "ANTHROPIC_MODEL")
    error_message = "Set ANTHROPIC_MODEL via the `model` input or the `env` map, not both."
  }

  validation {
    condition     = var.claude_code_oauth_token == "" || !contains(keys(var.env), "CLAUDE_CODE_OAUTH_TOKEN")
    error_message = "Set CLAUDE_CODE_OAUTH_TOKEN via the `claude_code_oauth_token` input or the `env` map, not both."
  }

  validation {
    condition     = !var.enable_ai_gateway || !contains(keys(var.env), "ANTHROPIC_BASE_URL")
    error_message = "enable_ai_gateway wires ANTHROPIC_BASE_URL automatically; remove it from the `env` map."
  }

  validation {
    condition     = !var.enable_ai_gateway || !contains(keys(var.env), "ANTHROPIC_AUTH_TOKEN")
    error_message = "enable_ai_gateway wires ANTHROPIC_AUTH_TOKEN automatically; remove it from the `env` map."
  }

  validation {
    condition     = !var.disable_auto_updater || !contains(keys(var.env), "DISABLE_AUTOUPDATER")
    error_message = "Set DISABLE_AUTOUPDATER via the `disable_auto_updater` input or the `env` map, not both."
  }
}

variable "model" {
  type        = string
  description = "Claude model identifier. Sets ANTHROPIC_MODEL when non-empty. Examples: \"opus\", \"sonnet\", \"claude-sonnet-4-5-20250929\"."
  default     = ""
}

variable "claude_code_oauth_token" {
  type        = string
  description = "Claude.ai subscription OAuth token. Sets CLAUDE_CODE_OAUTH_TOKEN when non-empty. Use a sensitive Terraform variable to keep this out of plan output."
  default     = ""
  sensitive   = true
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Route Claude Code through Coder AI Gateway. Wires ANTHROPIC_BASE_URL (to /api/v2/aibridge/anthropic) and ANTHROPIC_AUTH_TOKEN (to the workspace owner's session token). Requires Coder Premium with the AI Governance add-on and CODER_AIBRIDGE_ENABLED=true on the server."
  default     = false
}

variable "disable_auto_updater" {
  type        = bool
  description = "Turn off Claude Code's built-in auto-updater by setting DISABLE_AUTOUPDATER=1. Useful for air-gapped workspaces or when the image pins a specific version."
  default     = false
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
  description = "List of HTTPS URLs that return MCP JSON (same shape as `mcp`). Each is fetched and applied at user scope."
  default     = []

  validation {
    condition     = alltrue([for url in var.mcp_config_remote_path : can(regex("^https://", url))])
    error_message = "mcp_config_remote_path entries must use https:// to avoid MITM attacks and SSRF to plaintext-only internal services."
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

# Workspace and owner metadata powers the convenience inputs. Unconditionally
# declared so enable_ai_gateway can read them without count-indexed access.
data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  # Convenience inputs expand into env keys that Claude Code reads at runtime.
  # Each entry is included only when the corresponding input is set; the
  # validation blocks on var.env guarantee no key collision.
  model_env = var.model == "" ? {} : {
    ANTHROPIC_MODEL = var.model
  }

  oauth_token_env = var.claude_code_oauth_token == "" ? {} : {
    CLAUDE_CODE_OAUTH_TOKEN = var.claude_code_oauth_token
  }

  ai_gateway_env = var.enable_ai_gateway ? {
    ANTHROPIC_BASE_URL   = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
    ANTHROPIC_AUTH_TOKEN = data.coder_workspace_owner.me.session_token
  } : {}

  auto_updater_env = var.disable_auto_updater ? {
    DISABLE_AUTOUPDATER = "1"
  } : {}

  # Merge order is unimportant because validation rules out collisions, but
  # we put var.env last so a future change that relaxes validation falls
  # back to user-wins, not silent-convenience-wins.
  merged_env = merge(
    local.model_env,
    local.oauth_token_env,
    local.ai_gateway_env,
    local.auto_updater_env,
    var.env,
  )

  # All ARG_* values are base64-encoded in Terraform and decoded inside
  # install.sh. Base64 is the safe channel: the encoded form contains only
  # [A-Za-z0-9+/=], so an attacker-controlled string value (e.g. a template
  # parameter forwarded into `claude_code_version`) cannot break out of the
  # single-quoted shell literal. coder-utils takes the combined string,
  # writes it to $HOME/.coder-modules/claude-code/install.sh, and runs it. One file on
  # disk, one base64 round-trip, no /tmp wrapper.
  install_script = join("\n", [
    "#!/bin/bash",
    "set -euo pipefail",
    "",
    "export ARG_CLAUDE_CODE_VERSION='${base64encode(var.claude_code_version)}'",
    "export ARG_INSTALL_CLAUDE_CODE='${base64encode(tostring(var.install_claude_code))}'",
    "export ARG_CLAUDE_BINARY_PATH='${base64encode(var.claude_binary_path)}'",
    "export ARG_MCP='${base64encode(var.mcp)}'",
    "export ARG_MCP_CONFIG_REMOTE_PATH='${base64encode(jsonencode(var.mcp_config_remote_path))}'",
    "",
    file("${path.module}/scripts/install.sh"),
  ])
}

# Fan the merged env map (convenience inputs + var.env) out into one
# coder_env per entry. Keys are lifted out of their sensitivity taint with
# `nonsensitive` so Terraform can use them as for_each instance addresses;
# values retain any sensitivity attached by the caller's variable declaration
# (and by `claude_code_oauth_token` / the workspace owner's session token).
resource "coder_env" "env" {
  for_each = nonsensitive(toset(keys(local.merged_env)))
  agent_id = var.agent_id
  name     = each.key
  value    = local.merged_env[each.key]
}

module "coder-utils" {
  # Pinned to PR #842 branch on coder/registry until coder-utils@1.1.0 is published.
  source = "git::https://github.com/coder/registry.git//registry/coder/modules/coder-utils?ref=feat/coder-utils-optional-install-start"

  agent_id         = var.agent_id
  agent_name       = "claude-code"
  module_directory = "$HOME/.coder-modules/claude-code"

  display_name_prefix = "Claude Code"
  icon                = "/icon/claude.svg"

  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script

  install_script = local.install_script
}

# Passthrough of coder-utils' run-ordered, filtered sync-name list.
# claude-code adds no scripts of its own beyond what coder-utils creates for
# pre_install, install, and post_install, so downstream modules can gate
# behind this with `coder exp sync want`.
output "scripts" {
  description = "Ordered list of `coder exp sync` names for every coder_script this module creates. Use these to gate downstream scripts behind Claude Code's install with `coder exp sync want`."
  value       = module.coder-utils.scripts
}
