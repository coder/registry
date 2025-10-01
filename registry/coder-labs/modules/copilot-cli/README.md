---
display_name: Copilot CLI
description: GitHub Copilot CLI agent for AI-powered terminal assistance
icon: ../../../../.icons/github.svg
verified: false
tags: [agent, copilot, ai, github, cli, tasks]
---

# Copilot CLI

Run [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) in your workspace for AI-powered coding assistance directly from the terminal. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}
```

> [!NOTE]
> By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

## Prerequisites

- **Node.js v22+** and **npm v10+**
- **Active Copilot subscription** (GitHub Copilot Pro, Pro+, Business, or Enterprise)
- **GitHub authentication** via one of:
  - Direct token via `github_token` variable (highest priority)
  - Coder external authentication (recommended)
  - GitHub CLI (`gh auth login`)
  - Or use interactive login in Copilot CLI

## Examples

### Usage with Tasks and Advanced Configuration

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial task prompt for Copilot CLI."
  mutable     = true
}

module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  ai_prompt     = data.coder_parameter.ai_prompt.value
  copilot_model = "claude-sonnet-4.5"

  system_prompt = <<-EOT
    You are a helpful AI coding assistant working in a development environment.
    Always follow best practices and provide clear explanations for your suggestions.
    Focus on writing clean, maintainable code and helping with debugging tasks.
    Send a task status update to notify the user that you are ready for input, and then wait for user input.
  EOT

  allow_tools         = ["shell(git)", "shell(npm)", "write"]
  trusted_directories = ["/home/coder/workspace", "/tmp"]

  mcp_config = jsonencode({
    mcpServers = {
      custom_server = {
        command = "npx"
        args    = ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/files"]
      }
    }
  })

  pre_install_script = <<-EOT
    #!/bin/bash
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  EOT
}
```

### Direct Token Authentication

Use a GitHub token directly (OAuth token or Personal Access Token):

```tf
module "copilot_cli" {
  source       = "registry.coder.com/coder-labs/copilot-cli/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder/project"
  github_token = "your_github_token_here" # Or use data.coder_external_auth.github.access_token
}
```

## Configuration Files

This module creates and manages configuration files in `~/.config/copilot-cli/`:

- `config.json` - Copilot CLI settings (banner, theme, trusted directories)
- `mcp-config.json` - Model Context Protocol server definitions

The module automatically configures GitHub and Coder MCP servers, and merges any custom MCP servers you provide via `mcp_config`.

### Standalone Mode

Run and configure Copilot CLI as a standalone tool in your workspace.

```tf
module "copilot_cli" {
  source       = "registry.coder.com/coder-labs/copilot-cli/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  report_tasks = false
  cli_app      = true
}
```

### Custom Configuration

You can customize the entire Copilot CLI configuration:

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/projects"

  copilot_config = jsonencode({
    banner = "auto"
    theme  = "dark"
    trusted_folders = [
      "/home/coder/workspace",
      "/home/coder/projects"
    ]
  })
}
```

### System Prompt Configuration

You can customize the behavior of Copilot CLI by providing a system prompt that will be combined with task prompts:

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  system_prompt = <<-EOT
    You are a senior software engineer helping with code development.
    Always prioritize:
    - Code quality and best practices
    - Security considerations
    - Performance optimization
    - Clear documentation and comments
    
    When suggesting changes, explain the reasoning behind your recommendations.
    Send a task status update to notify the user that you are ready for input, and then wait for user input.
  EOT
}
```

## Authentication

This module works with multiple GitHub authentication methods in priority order:

**1. Direct Token :**

- **`github_token` variable**: Provide a GitHub OAuth token or Personal Access Token directly to the module

**2. Automatic detection:**

- **Coder External Auth**: OAuth tokens from GitHub external authentication configured in Coder
- **GitHub CLI**: OAuth tokens from `gh auth login` in the workspace

**3. Interactive fallback:**

- **Interactive login**: If no authentication is found, Copilot CLI will prompt users to login via the `/login` slash command

**No setup required** for automatic methods - the module detects and uses whatever authentication is available.

> **Note**: OAuth tokens work best with Copilot CLI. Personal Access Tokens may have limited functionality.

## Task Reporting

When `report_tasks = true` (default), this module automatically configures the **Coder MCP server** for task reporting integration:

- **Automatic Integration**: The Coder MCP server is added to the MCP configuration automatically
- **Task Status Updates**: Copilot CLI can report task progress to the Coder UI
- **No Manual Setup**: Works out-of-the-box with Coder's task reporting system
- **Custom MCP Compatible**: If you provide custom `mcp_config`, the Coder MCP server is added alongside your custom servers

The Coder MCP server enables Copilot CLI to:

- Report task status (working, complete, failure)
- Send progress updates to the Coder dashboard
- Integrate with Coder's AI task workflow system

To disable task reporting, set `report_tasks = false`.

## Troubleshooting

If you encounter any issues, check the log files in the `~/.copilot-module` directory within your workspace for detailed information.

```bash
# Installation logs
cat ~/.copilot-module/install.log

# Startup logs
cat ~/.copilot-module/agentapi-start.log

# Pre/post install script logs
cat ~/.copilot-module/pre_install.log
cat ~/.copilot-module/post_install.log
```

> [!NOTE]
> To use tasks with Copilot CLI, you must have an active GitHub Copilot subscription.
> The `workdir` variable is required and specifies the directory where Copilot CLI will run.

## References

- [GitHub Copilot CLI Documentation](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli)
- [Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
