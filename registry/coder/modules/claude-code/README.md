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
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
}
```

## Authentication

Two sensitive shortcuts are provided as dedicated variables. Every other env var goes through the `env` map.

- `anthropic_api_key`: sets `ANTHROPIC_API_KEY`. Marked sensitive.
- `claude_code_oauth_token`: sets `CLAUDE_CODE_OAUTH_TOKEN` (generate with `claude setup-token`). Marked sensitive.

```tf
# Claude.ai subscription
module "claude-code" {
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "5.0.0"
  agent_id                = coder_agent.main.id
  claude_code_oauth_token = var.claude_code_oauth_token
}
```

## Arbitrary environment variables (`env`)

Pass any Claude Code env var (or any custom var your pre/post scripts consume) through the `env` map. Each key/value pair becomes one `coder_env` resource on the agent.

```tf
module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key

  env = {
    ANTHROPIC_MODEL     = "opus"
    DISABLE_AUTOUPDATER = "1"
    MY_CUSTOM_VAR       = "hello"
  }
}
```

### Using a custom endpoint (AI Bridge, Bedrock, Vertex, LiteLLM, a private proxy)

Set the endpoint and token through `env`. Nothing is baked in; the [Claude Code env-vars reference](https://docs.claude.com/en/docs/claude-code/env-vars) lists every supported name.

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

> [!NOTE]
> `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` are rejected in `env` because they have dedicated sensitive variables (`anthropic_api_key`, `claude_code_oauth_token`). Every other env var is allowed.

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
- All Tasks, AgentAPI, Boundary, AI Bridge, and web-app variables removed. Compose dedicated modules or set env vars via the `env` map.
- `model`, `disable_autoupdater`, and `claude_md_path` variables removed. Set `ANTHROPIC_MODEL` and `DISABLE_AUTOUPDATER` via `env`. Claude Code discovers `~/.claude/CLAUDE.md` automatically.
- `workdir` removed. MCP applies at user scope.
- `install_via_npm` removed. Official installer only.
- `allowed_tools` / `disallowed_tools` removed. Write `~/.claude/settings.json` via `pre_install_script` with `permissions.allow` / `permissions.deny` arrays.
- `task_app_id` output removed.
