---
display_name: Codex CLI
icon: ../../../../.icons/openai.svg
description: Run Codex CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, codex, ai, openai, tasks]
---

# Codex CLI

Run Codex CLI in your workspace to access OpenAI's models through the Codex interface, with custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  openai_api_key = var.openai_api_key
  folder         = "/home/coder/project"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder/coder-login) module to your template
- OpenAI API key for Codex access

## Examples

### Run standalone

```tf
module "codex" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  openai_api_key = "..."
  folder         = "/home/coder/project"
}
```

### Tasks integration

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial prompt for the Codex CLI"
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}

module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  openai_api_key = "..."
  ai_prompt      = data.coder_parameter.ai_prompt.value
  folder         = "/home/coder/project"

  # Custom configuration for full auto mode
  base_config_toml = <<-EOT
    approval_policy = "never"
    preferred_auth_method = "apikey"
  EOT
}
```

> [!WARNING]
> This module configures Codex with a `workspace-write` sandbox that allows AI tasks to read/write files in the specified folder. While the sandbox provides security boundaries, Codex can still modify files within the workspace. Use this module _only_ in trusted environments and be aware of the security implications.

## How it Works

- **Install**: The module installs Codex CLI and sets up the environment
- **System Prompt**: If `codex_system_prompt` is set, writes the prompt to `AGENTS.md` in the `~/.codex/` directory
- **Start**: Launches Codex CLI in the specified directory, wrapped by AgentAPI
- **Configuration**: Sets `OPENAI_API_KEY` environment variable and passes `--model` flag to Codex CLI (if variables provided)

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

### Custom Configuration

For custom Codex configuration, use `base_config_toml` and/or `additional_mcp_servers`:

```tf
module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "2.0.0"
  # ... other variables ...

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

> [!NOTE]
> If no custom configuration is provided, the module uses secure defaults. The Coder MCP server is always included automatically. For containerized workspaces (Docker/Kubernetes), you may need `sandbox_mode = "danger-full-access"` to avoid permission issues. For advanced options, see [Codex config docs](https://github.com/openai/codex/blob/main/codex-rs/config.md).

## Troubleshooting

- Check installation and startup logs in `~/.codex-module/`
- Ensure your OpenAI API key has access to the specified model

> [!IMPORTANT]
> To use tasks with Codex CLI, ensure you have the `openai_api_key` variable set, and **you create a `coder_parameter` named `"AI Prompt"` and pass its value to the codex module's `ai_prompt` variable**. [Tasks Template Example](https://registry.coder.com/templates/coder-labs/tasks-docker).
> The module automatically configures Codex with your API key and model preferences.
> folder is a required variable for the module to function correctly.

## References

- [Codex CLI Documentation](https://github.com/openai/codex)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
