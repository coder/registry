---
display_name: Claude Code
description: Install and configure the Claude Code CLI in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, anthropic]
---

# Claude Code

Install and configure the [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) CLI in your workspace.

This module does three things:

1. Installs Claude Code via the [official installer](https://claude.ai/install.sh).
2. Exports environment variables to the Coder agent.
3. Optionally applies user-scope MCP server configuration.

It does not start Claude, create a web app, or orchestrate Tasks. Compose with dedicated modules for those concerns.

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

## Environment variables (`env`)

Pass any Claude Code env var (or any custom var your pre/post scripts consume) through the `env` map. Each key/value pair becomes one `coder_env` resource on the agent.

Declare your Terraform variable with `sensitive = true` to keep secrets out of plan output. Values retain their sensitivity when passed through the module.

```tf
variable "anthropic_api_key" {
  type      = string
  sensitive = true
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_API_KEY   = var.anthropic_api_key
    ANTHROPIC_MODEL     = "opus"
    DISABLE_AUTOUPDATER = "1"
    MY_CUSTOM_VAR       = "hello"
  }
}
```

### Claude.ai subscription

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    CLAUDE_CODE_OAUTH_TOKEN = var.claude_code_oauth_token
  }
}
```

### Coder AI Gateway

Route Claude Code through [Coder AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) for centralized auditing, token usage tracking, and MCP policy enforcement. Requires Coder Premium with the AI Governance add-on and `CODER_AIBRIDGE_ENABLED=true` on the server.

Point `ANTHROPIC_BASE_URL` at your deployment's `/api/v2/aibridge/anthropic` endpoint and authenticate with the workspace owner's session token via `ANTHROPIC_AUTH_TOKEN`. Claude Code reads both variables natively; no API key is required.

```tf
data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id

  env = {
    ANTHROPIC_BASE_URL   = "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic"
    ANTHROPIC_AUTH_TOKEN = data.coder_workspace_owner.me.session_token
  }
}
```

> [!NOTE]
> AI Gateway was previously named AI Bridge. The server-side endpoints and environment variables still use the `aibridge` prefix; only the product name changed.

### Other custom endpoints (Bedrock, Vertex, LiteLLM, a private proxy)

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

Set `install_claude_code = false` and point `claude_binary_path` at the directory containing the binary.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.0.0"
  agent_id            = coder_agent.main.id
  install_claude_code = false
  claude_binary_path  = "/opt/claude/bin"
}
```

## Scripts produced

By default this module creates exactly one `coder_script` on the agent: `Claude Code: Install Script`. Additional scripts appear only when you opt in:

| Script                             | Created when                  |
| ---------------------------------- | ----------------------------- |
| `Claude Code: Install Script`      | Always.                       |
| `Claude Code: Pre-Install Script`  | `pre_install_script` is set.  |
| `Claude Code: Post-Install Script` | `post_install_script` is set. |

No start script is produced in any configuration. Compose with a dedicated module (e.g. a future Tasks module) if you need one.

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

For template-admin setups where Claude Code should just work — CI agents, headless workspaces, AI coding agents that do not have a human to click through the first-run wizard or confirm bypass-permissions mode — pre-write `settings.json` and `~/.claude.json` via `pre_install_script`.

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

Keys verified live against Claude Code CLI v2.1.117:

| File                      | Key                                 | Effect                                                                                |
| ------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------- |
| `~/.claude/settings.json` | `permissions.defaultMode`           | `"bypassPermissions"`, `"acceptEdits"`, `"plan"`, `"auto"`, `"default"`, `"dontAsk"`. |
| `~/.claude/settings.json` | `permissions.allow` / `deny`        | Per-tool allowlist / denylist (e.g. `"Bash(git *)"`, `"Read(./secrets/**)"`).         |
| `~/.claude/settings.json` | `skipDangerousModePermissionPrompt` | Silences the one-time "enable bypassPermissions mode" consent banner.                 |
| `~/.claude.json`          | `hasCompletedOnboarding`            | Skips the first-run theme picker and welcome screens.                                 |

> [!NOTE]
> Pre-writing these files makes sense for automation and agents. Human users who expect the usual onboarding and per-project trust dialog should not use this pattern.

For one-off non-interactive runs, prefer the runtime flag instead of pre-writing config:

```bash
claude -p "$PROMPT" --dangerously-skip-permissions --permission-mode bypassPermissions
```

## Outputs

| Output    | Type           | Description                                                                                                                                                                                     |
| --------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts` | `list(string)` | `coder exp sync` names for every `coder_script` this module actually creates, in the run order `coder-utils` enforces (pre-install, install, post-install). Absent scripts are not in the list. |

Use `scripts` to gate a downstream module behind Claude Code's install:

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

Module logs live at `$HOME/.claude-module/`:

```bash
cat $HOME/.claude-module/install.log
cat $HOME/.claude-module/pre_install.log
cat $HOME/.claude-module/post_install.log
```

## Upgrading from v4.x

> [!CAUTION]
> If your template depends on Coder Tasks (`report_tasks`, `ai_prompt`, `continue`, `resume_session_id`, `enable_state_persistence`, `dangerously_skip_permissions`) or AgentAPI web-app integration (`web_app`, `cli_app`, `install_agentapi`, `agentapi_version`), stay on `v4.x` until the dedicated `claude-code-tasks` and `agentapi` modules ship. v5.0.0 removes all of that surface.

Breaking changes in v5.0.0:

- `claude_api_key`, `claude_code_oauth_token`, `model`, `disable_autoupdater`, `claude_md_path` removed as dedicated variables. Set them through `env` instead. The module now emits `ANTHROPIC_API_KEY` (the variable Claude Code actually reads), not `CLAUDE_API_KEY`.
- All Tasks, AgentAPI, Boundary, AI Bridge (now **AI Gateway**), and web-app variables removed. Compose dedicated modules or set env vars via `env`. See the AI Gateway example above for the replacement pattern.
- `workdir` removed. MCP applies at user scope.
- `install_via_npm` removed. Official installer only.
- `allowed_tools` / `disallowed_tools` removed. Write `~/.claude/settings.json` via `pre_install_script` with `permissions.allow` / `permissions.deny` arrays.
- `task_app_id` output removed.
