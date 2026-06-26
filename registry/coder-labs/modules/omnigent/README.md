---
display_name: Omnigent
icon: ../../../../.icons/omnigent.svg
description: Run a private Omnigent multi-agent coding server in your workspace.
verified: false
tags: [agent, omnigent, ai, multi-agent]
---

# Omnigent

Run a private [Omnigent](https://github.com/omnigent-dev) multi-agent coding orchestrator server inside your Coder workspace. Each workspace gets its own isolated Omnigent instance with a stable, derived admin password — no shared credentials, no manual password management.

The module installs Omnigent via the [official install script](https://omnigent.ai/install.sh), starts the server on a configurable port, waits for the health endpoint, and registers the local workspace as a host. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### With a custom port

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  port     = 7878
}
```

### With additional trusted origins

The module automatically trusts Coder app origins derived from `CODER_AGENT_URL` and `VSCODE_PROXY_URI` when those environment variables are available. If you expose Omnigent through another reverse proxy, add that browser origin explicitly:

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  allowed_origins = ["https://omnigent.example.com"]
}
```

### With AI tools (Omnigent + Claude Code + Codex)

Compose Omnigent alongside other AI agent modules to create a full multi-agent workspace. This example authenticates Claude Code and Codex through Coder AI Gateway.

```tf
module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "5.0.0"

  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = ">= 4.0.0"

  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
}

module "omnigent" {
  source  = "registry.coder.com/coder-labs/omnigent/coder"
  version = "1.0.0"

  agent_id = coder_agent.main.id
}
```

### Policies (server-wide)

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  server_config = <<-YAML
    policies:
      cap_tool_calls:
        type: function
        handler: omnigent.policies.builtins.safety.max_tool_calls_per_session
        factory_params:
          limit: 50
      require_approval:
        type: function
        handler: omnigent.policies.builtins.safety.ask_on_os_tools
  YAML
}
```

### Custom agents

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  agents = [
    {
      name    = "reviewer"
      content = <<-YAML
        name: reviewer
        instructions: You are an expert code reviewer. Focus on correctness, security, and clarity.
        executor:
          harness: claude-sdk
          model: claude-sonnet-4-5
      YAML
    }
  ]
}
```

### Bring-your-own config file

```tf
module "omnigent" {
  source             = "registry.coder.com/coder-labs/omnigent/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.main.id
  server_config_path = "/home/coder/.omnigent/server_config.yaml"
}
```

## Troubleshooting

Script logs are written to `~/.coder-modules/coder-labs/omnigent/logs/`. If the Omnigent app shows as unhealthy or the server fails to start, check:

```bash
cat ~/.coder-modules/coder-labs/omnigent/logs/server.log
cat ~/.coder-modules/coder-labs/omnigent/logs/start.log
cat ~/.coder-modules/coder-labs/omnigent/logs/install.log
cat ~/.coder-modules/coder-labs/omnigent/logs/host.log
```

The health endpoint is available at `http://localhost:<port>/health`. You can check it directly:

```bash
curl -sf http://localhost:6767/health && echo "healthy" || echo "not ready"
```

### Finding the admin password

The admin password is derived from the workspace ID at runtime. To retrieve it inside the workspace:

```bash
echo -n "$CODER_WORKSPACE_ID" | tr -d '-' | cut -c1-16
```
