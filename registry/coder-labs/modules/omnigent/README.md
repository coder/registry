---
display_name: Omnigent
icon: ../../../../.icons/omnigent.svg
description: Run a private Omnigent multi-agent coding server in your workspace.
verified: false
tags: [agent, omnigent, ai, multi-agent]
---

# Omnigent

Run a private [Omnigent](https://github.com/omnigent-dev) multi-agent coding orchestrator server inside your Coder workspace. Each workspace gets its own isolated Omnigent instance with a stable, derived admin password — no shared credentials, no manual password management.

The module installs Omnigent via `uv tool install`, starts the server on a configurable port, waits for the health endpoint, and registers the local workspace as a host. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Standalone with default settings

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### With a custom port

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  port     = 7878
}
```

### With AI tools (Omnigent + Claude Code + Codex)

Compose Omnigent alongside other AI agent modules to create a full multi-agent workspace:

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = var.openai_api_key
}

module "claude_code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = ">= 4.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
}
```

## Troubleshooting

Server logs are written to `~/.coder-modules/coder-labs/omnigent/logs/start.log`. If the Omnigent app shows as unhealthy or the server fails to start, check:

```bash
cat ~/.coder-modules/coder-labs/omnigent/logs/start.log
cat ~/.coder-modules/coder-labs/omnigent/logs/install.log
```

The health endpoint is available at `http://localhost:<port>/health`. You can check it directly:

```bash
curl -sf http://localhost:6767/health && echo "healthy" || echo "not ready"
```
