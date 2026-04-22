---
display_name: Claude Code
description: Install and configure the Claude Code CLI in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, anthropic]
---

# Claude Code

Install and configure the [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) CLI in your workspace.

This module does two things:

1. Installs Claude Code via the [official installer](https://claude.ai/install.sh).
2. Optionally applies user-scope MCP server configuration.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }
}
```

## Environment variables (`env`) and convenience inputs

The convenience inputs `model`, `claude_code_oauth_token`, `enable_ai_gateway`, and `disable_auto_updater` cover the most common Claude Code configuration. For anything else, pass raw env vars through the `env` map. The convenience inputs and the `env` map merge into one set. Setting the same env key through both routes fails before the workspace deploys.

```tf
variable "anthropic_api_key" {
  type      = string
  sensitive = true
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  model                = "opus"
  disable_auto_updater = true

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
    MY_CUSTOM_VAR     = "hello"
  }
}
```

### Claude.ai subscription

```tf
variable "claude_code_oauth_token" {
  type      = string
  sensitive = true
}

module "claude-code" {
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "5.0.0"
  agent_id                = coder_agent.main.id
  claude_code_oauth_token = var.claude_code_oauth_token
}
```

### Coder AI Gateway

Route Claude Code through [Coder AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) for centralized auditing and token usage tracking. Requires Coder Premium with the AI Governance add-on and `CODER_AIBRIDGE_ENABLED=true` on the server.

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
}
```

`enable_ai_gateway = true` wires `ANTHROPIC_BASE_URL` to your deployment's `/api/v2/aibridge/anthropic` endpoint and `ANTHROPIC_AUTH_TOKEN` to the workspace owner's session token. Claude Code reads both directly, so no API key is required.

> [!NOTE]
> AI Gateway was previously named AI Bridge. The server-side endpoints and environment variables still use the `aibridge` prefix; only the product name changed.

### AWS Bedrock

Route Claude Code through [AWS Bedrock](https://docs.claude.com/en/docs/claude-code/amazon-bedrock) to access Claude models via your AWS account. Requires an AWS account with Bedrock access, the target Claude models enabled in the Bedrock console, and IAM permissions that allow `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream`.

Pick either an access key pair or a Bedrock bearer token for auth; do not set both.

```tf
variable "aws_bearer_token_bedrock" {
  type      = string
  sensitive = true
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  model = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"

  env = {
    CLAUDE_CODE_USE_BEDROCK  = "1"
    AWS_REGION               = "us-east-1"
    AWS_BEARER_TOKEN_BEDROCK = var.aws_bearer_token_bedrock
    # Or, with access keys instead of the bearer token:
    # AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    # AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
  }
}
```

### Google Vertex AI

Route Claude Code through [Google Vertex AI](https://docs.claude.com/en/docs/claude-code/google-vertex-ai). Requires a GCP project with Vertex AI enabled, Claude models enabled via Model Garden, and a service account with the Vertex AI User role.

The service account JSON must be written to disk where Claude can read it, so gcloud authentication happens in `pre_install_script`:

```tf
variable "vertex_sa_json" {
  type        = string
  description = "Full JSON body of a GCP service account key with Vertex AI User."
  sensitive   = true
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  model = "claude-sonnet-4@20250514"

  env = {
    CLAUDE_CODE_USE_VERTEX         = "1"
    ANTHROPIC_VERTEX_PROJECT_ID    = "your-gcp-project-id"
    CLOUD_ML_REGION                = "global"
    GOOGLE_APPLICATION_CREDENTIALS = "$HOME/.config/gcloud/sa.json"
    VERTEX_SA_JSON                 = var.vertex_sa_json
  }

  pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    mkdir -p "$HOME/.config/gcloud"
    printf '%s' "$VERTEX_SA_JSON" > "$HOME/.config/gcloud/sa.json"
    chmod 600 "$HOME/.config/gcloud/sa.json"
  EOT
}
```

Install `gcloud` itself in the workspace image, in `pre_install_script`, or via a separate Coder module; this example leaves that choice to the template author.

### Other custom endpoints (LiteLLM, a private proxy)

Same pattern with your own endpoint and token. The [Claude Code env-vars reference](https://docs.claude.com/en/docs/claude-code/env-vars) lists every supported name.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_BASE_URL   = "https://proxy.example.com/anthropic"
    ANTHROPIC_AUTH_TOKEN = var.proxy_token
  }
}
```

## MCP configuration

MCP servers are applied at **user scope** via `claude mcp add-json --scope user`. They end up in `~/.claude.json` and apply across every project the user opens.

### Inline

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }

  mcp = jsonencode({
    mcpServers = {
      github = {
        command = "npx"
        args    = ["-y", "@modelcontextprotocol/server-github"]
      }
    }
  })
}
```

### From remote URLs

Each URL must return JSON in the shape `{"mcpServers": {...}}`. `Content-Type` is not enforced; `text/plain` and `application/json` both work.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }

  mcp_config_remote_path = [
    "https://raw.githubusercontent.com/coder/coder/main/.mcp.json",
  ]
}
```

## Pinning a version

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.0.0"
  agent_id            = coder_agent.main.id
  claude_code_version = "2.0.62"
}
```

## Using a pre-installed binary

`claude_binary_path` is only consulted when `install_claude_code = false`. The official installer always drops the binary at `$HOME/.local/bin/claude` and does not accept a custom destination, so combining `install_claude_code = true` with a custom `claude_binary_path` is rejected before the workspace deploys.

To use a binary you bake into the image (or install via a separate module), set `install_claude_code = false` and point `claude_binary_path` at the directory containing it:

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.0.0"
  agent_id            = coder_agent.main.id
  install_claude_code = false
  claude_binary_path  = "/opt/claude/bin"
}
```

## Extending with pre/post install scripts

Use `pre_install_script` and `post_install_script` for custom setup (e.g. writing `~/.claude/settings.json` permission rules, installing cloud SDKs, pulling secrets).

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }

  pre_install_script = <<-EOT
    #!/bin/bash
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<'JSON'
    {
      "permissions": {
        "deny": ["Read(./.env)", "Read(./secrets/**)"]
      }
    }
    JSON
  EOT
}
```

## Unattended mode (skip setup wizard and permission prompts)

For templates that need Claude Code to run without human interaction (CI agents, headless workspaces, AI coding agents that cannot click through the first-run wizard or confirm bypass-permissions mode), pre-write `settings.json` and `~/.claude.json` via `pre_install_script`.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }

  pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    # Settings: default to bypassPermissions so tool calls do not prompt,
    # silence the "dangerous mode" consent banner, and keep a deny list for
    # anything the agent must never read.
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<'JSON'
    {
      "permissions": {
        "defaultMode": "bypassPermissions",
        "deny": ["Read(./.env)", "Read(./secrets/**)", "Read(**/*.pem)"]
      },
      "skipDangerousModePermissionPrompt": true
    }
    JSON

    # User config: skip the theme and first-run onboarding flow. The official
    # installer creates ~/.claude.json before this pre_install_script runs,
    # so merge rather than overwrite to preserve installer-managed keys
    # (userID, autoUpdates, migrationVersion, firstStartTime).
    if [ -f "$HOME/.claude.json" ]; then
      tmp=$(mktemp)
      jq '. + {hasCompletedOnboarding: true}' "$HOME/.claude.json" > "$tmp" \
        && mv "$tmp" "$HOME/.claude.json"
    else
      printf '%s\n' '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
    fi
  EOT
}
```

Key reference: [`permissions`](https://docs.claude.com/en/docs/claude-code/settings) in `~/.claude/settings.json`, [`hasCompletedOnboarding`](https://docs.claude.com/en/docs/claude-code/settings) in `~/.claude.json`.

For one-off non-interactive runs, prefer a runtime flag over pre-writing config:

```bash
claude -p "$PROMPT" --dangerously-skip-permissions --permission-mode bypassPermissions
```

## Outputs

`scripts` is the list of script names this module creates, in run order. Use it with `coder exp sync` to make another `coder_script` wait until Claude Code finishes installing:

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "wait_for_claude" {
  agent_id     = coder_agent.main.id
  display_name = "Wait for Claude Code"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    coder exp sync want my-downstream-script ${join(" ", module.claude-code.scripts)}
    coder exp sync start my-downstream-script
    # your logic here
    coder exp sync complete my-downstream-script
  EOT
}
```

## Troubleshooting

Module logs are written to `$HOME/.coder-modules/claude-code/`:

```bash
cat $HOME/.coder-modules/claude-code/install.log
cat $HOME/.coder-modules/claude-code/pre_install.log
cat $HOME/.coder-modules/claude-code/post_install.log
```

## Upgrading from v4.x

> [!CAUTION]
> If your template depends on Coder Tasks (`report_tasks`, `ai_prompt`, `continue`, `resume_session_id`, `enable_state_persistence`, `dangerously_skip_permissions`) or AgentAPI web-app integration (`web_app`, `cli_app`, `install_agentapi`, `agentapi_version`), stay on `v4.x` until the dedicated `claude-code-tasks` and `agentapi` modules ship. v5.0.0 removes all of that surface.

Breaking changes in v5.0.0:

- `claude_api_key` removed. Set `ANTHROPIC_API_KEY` through the `env` map (the variable Claude Code actually reads, not `CLAUDE_API_KEY`).
- `claude_md_path` removed. Write the file in `pre_install_script`.
- `disable_autoupdater` renamed to `disable_auto_updater`.
- `model`, `claude_code_oauth_token`, and the AI Gateway wiring stay as dedicated inputs (`model`, `claude_code_oauth_token`, `enable_ai_gateway`); see the examples above.
- All Tasks, AgentAPI, Boundary, and web-app variables removed. Use dedicated modules instead, or set env vars through the `env` map.
- `workdir` removed. MCP applies at user scope.
- `install_via_npm` removed. Official installer only.
- `allowed_tools` / `disallowed_tools` removed. Write `~/.claude/settings.json` via `pre_install_script` with `permissions.allow` / `permissions.deny` arrays.
- `task_app_id` output removed.
