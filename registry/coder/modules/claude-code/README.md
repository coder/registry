---
display_name: Claude Code
description: Run Claude Code in your workspace
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude-code, ai, tasks]
---

# Claude Code

Run the [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) agent in your workspace to generate code and perform tasks.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "2.2.1"
  agent_id            = coder_agent.example.id
  folder              = "/home/coder"
  install_claude_code = true
  claude_code_version = "latest"
}
```

> **Security Notice**: This module uses the [`--dangerously-skip-permissions`](https://docs.anthropic.com/en/docs/claude-code/cli-usage#cli-flags) flag when running Claude Code. This flag
> bypasses standard permission checks and allows Claude Code broader access to your system than normally permitted. While
> this enables more functionality, it also means Claude Code can potentially execute commands with the same privileges as
> the user running it. Use this module _only_ in trusted environments and be aware of the security implications.

> [!NOTE]
> By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template

The `codercom/oss-dogfood:latest` container image can be used for testing on container-based workspaces.

## Examples

### Run in the background and report tasks (Experimental)

> This functionality is in early access as of Coder v2.21 and is still evolving.
> For now, we recommend testing it in a demo or staging environment,
> rather than deploying to production
>
> Learn more in [the Coder documentation](https://coder.com/docs/tutorials/ai-agents)
>
> Join our [Discord channel](https://discord.gg/coder) or
> [contact us](https://coder.com/contact) to get help or share feedback.

```tf
variable "anthropic_api_key" {
  type        = string
  description = "The Anthropic API key"
  sensitive   = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for Claude Code"
  mutable     = true
}

# Set the prompt and system prompt for Claude Code via environment variables
resource "coder_agent" "main" {
  # ...
  env = {
    CODER_MCP_CLAUDE_API_KEY       = var.anthropic_api_key # or use a coder_parameter
    CODER_MCP_CLAUDE_TASK_PROMPT   = data.coder_parameter.ai_prompt.value
    CODER_MCP_APP_STATUS_SLUG      = "claude-code"
    CODER_MCP_CLAUDE_SYSTEM_PROMPT = <<-EOT
      You are a helpful assistant that can help with code.
    EOT
  }
}

module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "2.2.1"
  agent_id            = coder_agent.example.id
  folder              = "/home/coder"
  install_claude_code = true
  claude_code_version = "1.0.40"

  # Enable experimental features
  experiment_report_tasks = true
}
```

## Run standalone

Run Claude Code as a standalone app in your workspace. This will install Claude Code and run it without any task reporting to the Coder UI.

```tf
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "2.2.1"
  agent_id            = coder_agent.example.id
  folder              = "/home/coder"
  install_claude_code = true
  claude_code_version = "latest"

  # Icon is not available in Coder v2.20 and below, so we'll use a custom icon URL
  icon = "https://registry.npmmirror.com/@lobehub/icons-static-png/1.24.0/files/dark/claude-color.png"
}
```

## Troubleshooting

The module will create log files in the workspace's `~/.claude-module` directory. If you run into any issues, look at them for more information.
