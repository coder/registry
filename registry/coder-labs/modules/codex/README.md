---
display_name: Codex CLI
icon: ../../../../.icons/openai.svg
description: Run Codex CLI in your workspace with optional Tasks integration
verified: true
tags: [agent, codex, ai, openai, tasks, aibridge]
---

# Codex CLI

Install Codex CLI in your workspace with optional Coder Tasks integration via [AgentAPI](https://github.com/coder/agentapi). The module supports AI Bridge, custom install scripts, and MCP server configuration.

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "4.2.0"
  agent_id       = coder_agent.example.id
  openai_api_key = var.openai_api_key
  workdir        = "/home/coder/project"
}
```

## Prerequisites

- OpenAI API key for Codex access (not required when `enable_aibridge = true`)

## Examples

### Standalone (no Tasks UI)

Use `enable_tasks = false` to install Codex without AgentAPI/Tasks. `workdir` is optional in this mode.

```tf
module "codex" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "4.2.0"
  agent_id       = coder_agent.example.id
  openai_api_key = "..."
  enable_tasks   = false
  # workdir not required in standalone mode
}
```

### Usage with AI Bridge

[AI Bridge](https://coder.com/docs/ai-coder/ai-bridge) is a Premium Coder feature that provides centralized LLM proxy management. Set `enable_aibridge = true` to use it (requires Coder 2.30+). When AI Bridge is enabled, authentication uses the workspace owner session token, so `openai_api_key` should be omitted.

```tf
module "codex" {
  source          = "registry.coder.com/coder-labs/codex/coder"
  version         = "4.2.0"
  agent_id        = coder_agent.example.id
  enable_aibridge = true
  enable_tasks    = false # Standalone mode - just CLI, no Tasks UI
  # workdir not required in standalone mode
}
```

For Tasks integration, add `enable_aibridge = true` to the [Usage with Tasks](#usage-with-tasks) example below.

When `enable_aibridge = true`, the module:

- Configures Codex to use the AI Bridge profile with `base_url` pointing to `${data.coder_workspace.me.access_url}/api/v2/aibridge/openai/v1` and `env_key` pointing to the workspace owner's session token
- Sets `profile = "aibridge"` at the top of `config.toml` so Codex uses AI Bridge by default

```toml
profile = "aibridge"

[model_providers.aibridge]
name = "AI Bridge"
base_url = "https://example.coder.com/api/v2/aibridge/openai/v1"
env_key = "CODER_AIBRIDGE_SESSION_TOKEN"
wire_api = "responses"

[profiles.aibridge]
model_provider = "aibridge"
model = "<model>" # as configured in the module input
model_reasoning_effort = "<model_reasoning_effort>" # as configured in the module input
```

Codex uses the AI Bridge profile by default, so running `codex` manually does not require `--profile aibridge`.
Template build will fail if `openai_api_key` is provided alongside `enable_aibridge = true`.

### Usage with Tasks

This example shows how to configure Codex with Coder tasks.

```tf
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = module.codex.task_app_id
}

data "coder_task" "me" {}

module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "4.2.0"
  agent_id       = coder_agent.example.id
  openai_api_key = "..."
  ai_prompt      = data.coder_task.me.prompt
  workdir        = "/home/coder/project"

  # Optional: route through AI Bridge (Premium feature)
  # enable_aibridge = true
}
```

### Advanced Configuration

This example shows additional configuration options for custom models, MCP servers, and base configuration.

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "4.2.0"
  agent_id       = coder_agent.example.id
  openai_api_key = "..."
  workdir        = "/home/coder/project"

  codex_version = "0.1.0"  # Pin to a specific version
  codex_model   = "gpt-4o" # Custom model

  # Override default configuration
  base_config_toml = <<-EOT
    sandbox_mode = "danger-full-access"
    approval_policy = "never"
    preferred_auth_method = "apikey"
  EOT

  # Add extra MCP servers
  additional_mcp_servers = <<-EOT
    [mcp_servers.GitHub]
    command = "npx"
    args = ["-y", "@modelcontextprotocol/server-github"]
    type = "stdio"
  EOT
}
```

> [!WARNING]
> This module configures Codex with a `workspace-write` sandbox that allows AI tasks to read/write files in the specified workdir. While the sandbox provides security boundaries, Codex can still modify files within the workspace. Use this module _only_ in trusted environments and be aware of the security implications.

## How it Works

- **Install**: Installs Codex CLI and prepares configuration.
- **System Prompt**: If `codex_system_prompt` is set, writes it to `~/.codex/AGENTS.md`.
- **Start**: When `enable_tasks = true`, launches Codex via AgentAPI in the selected `workdir`. When `enable_tasks = false`, only the install script runs.
- **Configuration**: Writes `OPENAI_API_KEY` when provided, and sets the AI Bridge profile when `enable_aibridge = true`.
- **Session Continuity**: When `continue = true` (default), task sessions are tracked in `~/.codex-module/.codex-task-session` for resume on restart. Set `continue = false` to always start fresh sessions.

## Configuration

### Default Configuration

When no custom `base_config_toml` is provided, the module uses these secure defaults:

```toml
sandbox_mode = "workspace-write"
approval_policy = "never"
preferred_auth_method = "apikey"

[sandbox_workspace_write]
network_access = true
```

> [!NOTE]
> If no custom configuration is provided, the module uses secure defaults. The Coder MCP server is always included automatically. For containerized workspaces (Docker/Kubernetes), you may need `sandbox_mode = "danger-full-access"` to avoid permission issues. For advanced options, see [Codex config docs](https://github.com/openai/codex/blob/main/codex-rs/config.md).

## Troubleshooting

- Tasks mode: check installation/startup logs in `~/.codex-module/`.
- Standalone mode: review the workspace script output for the "Install Codex" script.
- Ensure your OpenAI API key has access to the specified model (unless using AI Bridge).

> [!IMPORTANT]
> To use tasks with Codex CLI, ensure you have the `openai_api_key` variable set. [Tasks Template Example](https://registry.coder.com/templates/coder-labs/tasks-docker).
> The module automatically configures Codex with your API key and model preferences.
> `workdir` is required when `enable_tasks = true` (default). For standalone CLI usage, set `enable_tasks = false` and `workdir` becomes optional.

## References

- [Codex CLI Documentation](https://github.com/openai/codex)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
- [AI Bridge](https://coder.com/docs/ai-coder/ai-bridge)
