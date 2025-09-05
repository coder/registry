---
display_name: Claude Code
description: Run the Claude Code agent in your workspace to generate code and perform tasks.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, tasks, anthropic]
---

# Claude Code

Run the [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) agent in your workspace to generate code and perform tasks. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "3.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}
```

> [!WARNING]
> **Security Notice**: This module uses the `--dangerously-skip-permissions` flag when running Claude Code tasks. This flag bypasses standard permission checks and allows Claude Code broader access to your system than normally permitted. While this enables more functionality, it also means Claude Code can potentially execute commands with the same privileges as the user running it. Use this module _only_ in trusted environments and be aware of the security implications.

## Prerequisites

- An **Anthropic API key** is required for tasks. You can get one from the [Anthropic Console](https://console.anthropic.com/dashboard).

## Examples

### Usage with Tasks and Advanced Configuration

This example shows how to configure the Claude Code module with a task prompt, API key, and other custom settings.

```tf
variable "anthropic_api_key" {
  type        = string
  description = "The Anthropic API key."
  sensitive   = true
}

data "coder_parameter" "task_prompt" {
  type        = "string"
  name        = "AI Task Prompt"
  default     = ""
  description = "Initial task prompt for Claude Code."
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31" # Use a recent version
  agent_id = coder_agent.example.id
}

module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "3.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  # --- Authentication ---
  claude_api_key = var.anthropic_api_key # required for tasks

  # --- Versioning ---
  claude_code_version = "1.0.82" # Pin to a specific version
  agentapi_version    = "v0.6.1"

  # --- Task Configuration ---
  task_prompt = data.coder_parameter.task_prompt.value
  continue    = true # will fail in a new workspace with no conversation/session to continue
  model       = "sonnet"

  # --- Permissions & Tools ---
  permission_mode = "plan"

  # --- MCP Configuration ---
  mcp = <<-EOF
  {
    "mcpServers": {
      "my-custom-tool": {
        "command": "my-tool-server"
        "args": ["--port", "8080"]
      }
    }
  }
  EOF
}
```

### Standalone Mode

Run Claude Code as a standalone CLI in your workspace without task reporting to the Coder UI.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "3.0.0"
  agent_id            = coder_agent.example.id
  workdir             = "/home/coder"
  install_claude_code = true
  claude_code_version = "latest"
  report_tasks        = false
  cli_app             = true
}
```

## Environment Variables

The module can be further configured using environment variables set on the Coder agent. This allows for more advanced or dynamic setups.

| Variable                         | Description                                                                   | Default                        |
| -------------------------------- | ----------------------------------------------------------------------------- | ------------------------------ |
| `CLAUDE_API_KEY`                 | Your Anthropic API key.                                                       | `""`                           |
| `CODER_MCP_CLAUDE_SYSTEM_PROMPT` | A custom system prompt for Claude.                                            | "Send a task status update..." |
| `CODER_MCP_CLAUDE_CODER_PROMPT`  | A custom coder prompt for Claude.                                             | `""`                           |
| `CODER_MCP_CLAUDE_CONFIG_PATH`   | Path to the Claude configuration file.                                        | `~/.claude.json`               |
| `CODER_MCP_CLAUDE_MD_PATH`       | Path to a `CLAUDE.md` file for project-specific instructions.                 | `~/.claude/CLAUDE.md`          |
| `CLAUDE_CODE_USE_BEDROCK`        | Set to `"true"` to use Amazon Bedrock. Requires additional AWS configuration. | `""`                           |

An example of setting these on a `coder_agent` resource:

```tf
resource "coder_agent" "main" {
  # ... other agent config
  env = {
    CLAUDE_API_KEY                 = var.anthropic_api_key
    CODER_MCP_CLAUDE_SYSTEM_PROMPT = <<-EOT
      You are a helpful assistant that can help with code.
    EOT
  }
}
```

## Troubleshooting

If you encounter any issues, check the log files in the `~/.claude-module` directory within your workspace for detailed information.

```bash
# Installation logs
cat ~/.claude-module/install.log

# Startup logs
cat ~/.claude-module/agentapi-start.log

# Pre/post install script logs
cat ~/.claude-module/pre_install.log
cat ~/.claude-module/post_install.log
```

> [!NOTE]
> To use tasks with Claude Code, you must provide an `anthropic_api_key`. It's recommended to use a `coder_parameter` for the `task_prompt` to allow users to input tasks from the Coder UI. The `workdir` variable is required and specifies the directory where Claude Code will run.

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
