---
display_name: Claude Code
description: Install and configure the Claude Code CLI in your workspace.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, anthropic, aibridge]
---

# Claude Code

Install and configure the [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) CLI in your workspace.

This module does three things:

1. Installs Claude Code via the [official installer](https://claude.ai/install.sh).
2. Wires up authentication through environment variables.
3. Optionally applies user-scope MCP server configuration.

It does not start Claude, create a web app, or orchestrate Tasks. For those, see the dedicated `claude-code-tasks`, `agentapi`, and `boundary` modules.

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
- `enable_aibridge = true`: Routes through Coder [AI Bridge](https://coder.com/docs/ai-coder/ai-bridge). Sets `ANTHROPIC_AUTH_TOKEN` (workspace owner session token) and `ANTHROPIC_BASE_URL`. Cannot combine with an API key or OAuth token.

```tf
# Claude.ai subscription
module "claude-code" {
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "5.0.0"
  agent_id                = coder_agent.main.id
  claude_code_oauth_token = var.claude_code_oauth_token
}

# AI Bridge (Premium, requires Coder >= 2.29.0)
module "claude-code" {
  source          = "registry.coder.com/coder/claude-code/coder"
  version         = "5.0.0"
  agent_id        = coder_agent.main.id
  enable_aibridge = true
}
```

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

## Using AWS Bedrock or Google Vertex

The module does not own Bedrock/Vertex env vars; set them yourself with `coder_env` resources.

```tf
resource "coder_env" "bedrock_use" {
  agent_id = coder_agent.main.id
  name     = "CLAUDE_CODE_USE_BEDROCK"
  value    = "1"
}

resource "coder_env" "aws_region" {
  agent_id = coder_agent.main.id
  name     = "AWS_REGION"
  value    = "us-east-1"
}

resource "coder_env" "aws_bearer_token_bedrock" {
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.0.0"
  agent_id = coder_agent.main.id
  model    = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
```

See the [Bedrock](https://docs.claude.com/en/docs/claude-code/amazon-bedrock) and [Vertex AI](https://docs.claude.com/en/docs/claude-code/google-vertex-ai) pages for additional env var options.

## Troubleshooting

Module logs live at `$HOME/.claude-module/`:

```bash
cat $HOME/.claude-module/install.log
cat $HOME/.claude-module/pre_install.log
cat $HOME/.claude-module/post_install.log
```

## Upgrading from v4.x

Breaking changes in v5.0.0:

- `claude_api_key` renamed to `anthropic_api_key` and emits `ANTHROPIC_API_KEY` (not `CLAUDE_API_KEY`). This matches Claude Code's documented variable.
- All Tasks, AgentAPI, Boundary, and web-app variables removed. See the dedicated modules.
- `workdir` removed. MCP applies at user scope. Project-specific config belongs in the repo.
- `install_via_npm` removed. Official installer only.
- `allowed_tools` / `disallowed_tools` removed. Write `~/.claude/settings.json` via `pre_install_script` with `permissions.allow` / `permissions.deny` arrays.
- `task_app_id` output removed. Read it from the Tasks module.
- AI Bridge now uses `ANTHROPIC_AUTH_TOKEN` instead of `CLAUDE_API_KEY`.
