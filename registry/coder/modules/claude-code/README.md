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
2. Wires up authentication through the environment variables Claude Code reads natively.
3. Optionally applies user-scope MCP server configuration.

It does not start Claude, create a web app, or orchestrate Tasks. Compose with dedicated modules for those concerns.

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
}
```

## Authentication

Choose one of:

- `anthropic_api_key`: Anthropic API key. Sets `ANTHROPIC_API_KEY`.
- `claude_code_oauth_token`: Long-lived Claude.ai subscription token (generate with `claude setup-token`). Sets `CLAUDE_CODE_OAUTH_TOKEN`.

```tf
# Claude.ai subscription
module "claude-code" {
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "5.0.0"
  agent_id                = coder_agent.main.id
  claude_code_oauth_token = var.claude_code_oauth_token
}
```

For custom endpoints (AI Bridge, Bedrock, Vertex AI, LiteLLM, a private gateway), set the env vars Claude Code reads directly via `coder_env`:

```tf
# Example: route through a custom Anthropic-compatible proxy.
resource "coder_env" "anthropic_base_url" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_BASE_URL"
  value    = "https://proxy.example.com/anthropic"
}

resource "coder_env" "anthropic_auth_token" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = var.proxy_token
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id
}
```

See Claude Code's [environment variables reference](https://docs.claude.com/en/docs/claude-code/env-vars) for the full list (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_PROJECT_ID`, etc.).

## MCP configuration

MCP servers are applied at **user scope** via `claude mcp add-json --scope user`. They end up in `~/.claude.json` and apply across every project the user opens.

### Inline

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key

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
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key

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

## Extending with pre/post install scripts

Use `pre_install_script` and `post_install_script` for custom setup (e.g. writing `~/.claude/settings.json` permission rules, installing cloud SDKs, pulling secrets).

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key

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

## Troubleshooting

Module logs live at `$HOME/.claude-module/`:

```bash
cat $HOME/.claude-module/install.log
cat $HOME/.claude-module/pre_install.log
cat $HOME/.claude-module/post_install.log
```

## Upgrading from v4.x

Breaking changes in v5.0.0:

- `claude_api_key` renamed to `anthropic_api_key`. Now sets `ANTHROPIC_API_KEY` (the variable Claude Code actually reads), not `CLAUDE_API_KEY`.
- All Tasks, AgentAPI, Boundary, AI Bridge, and web-app variables removed. Compose dedicated modules or set env vars via `coder_env`.
- `workdir` removed. MCP applies at user scope.
- `claude_md_path` removed. Claude Code discovers `~/.claude/CLAUDE.md` automatically.
- `install_via_npm` removed. Official installer only.
- `allowed_tools` / `disallowed_tools` removed. Write `~/.claude/settings.json` via `pre_install_script` with `permissions.allow` / `permissions.deny` arrays.
- `task_app_id` output removed.
