---
display_name: Copilot CLI
description: GitHub Copilot CLI agent for AI-powered terminal assistance
icon: ../../../../.icons/github.svg
verified: false
tags: [agent, copilot, ai, github, tasks]
---

# Copilot CLI

Run [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) in your workspace for AI-powered coding assistance directly from the terminal. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}
```

> [!IMPORTANT]
> This example assumes you have [Coder external authentication](https://coder.com/docs/admin/external-auth) configured with `id = "github"`. If not, you can provide a direct token using the `github_token` variable.

> [!NOTE]
> By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

## Prerequisites

- **Node.js v22+** and **npm v10+**
- **[Active Copilot subscription](https://docs.github.com/en/copilot/about-github-copilot/subscription-plans-for-github-copilot)** (GitHub Copilot Pro, Pro+, Business, or Enterprise)
- **GitHub authentication** via one of:
  - [Coder external authentication](https://coder.com/docs/admin/external-auth) (recommended)
  - Direct token via `github_token` variable
  - Interactive login in Copilot CLI

## Examples

### Usage with Tasks

For development environments where you want Copilot CLI to have full access to tools and automatically resume sessions:

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
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  ai_prompt       = data.coder_parameter.ai_prompt.value
  copilot_model   = "claude-sonnet-4.5"
  allow_all_tools = true
  resume_session  = true

  trusted_directories = ["/home/coder", "/tmp"]
}
```

### Advanced Configuration

Customize tool permissions, MCP servers, and Copilot CLI settings:

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  # Tool permissions
  allow_tools         = ["shell(git)", "shell(npm)", "write"]
  trusted_directories = ["/home/coder/workspace", "/tmp"]

  # Custom Copilot CLI configuration
  copilot_config = jsonencode({
    banner = "auto"
    theme  = "dark"
    trusted_folders = [
      "/home/coder/workspace",
      "/home/coder/project"
    ]
  })

  # MCP server configuration
  mcp_config = jsonencode({
    mcpServers = {
      filesystem = {
        command     = "npx"
        args        = ["-y", "@modelcontextprotocol/server-filesystem", "/home/coder/workspace"]
        description = "Provides file system access to the workspace"
        name        = "Filesystem"
        timeout     = 3000
        type        = "local"
        tools       = ["*"]
        trust       = true
      }
      playwright = {
        command     = "npx"
        args        = ["-y", "@playwright/mcp@latest", "--headless", "--isolated"]
        description = "Browser automation for testing and previewing changes"
        name        = "Playwright"
        timeout     = 5000
        type        = "local"
        tools       = ["*"]
        trust       = false
      }
    }
  })

  # Pre-install Node.js if needed
  pre_install_script = <<-EOT
    #!/bin/bash
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  EOT
}
```

> [!NOTE]
> GitHub Copilot CLI does not automatically install MCP servers. You have two options:
>
> - Use `npx -y` in the MCP config (shown above) to auto-install on each run
> - Pre-install MCP servers in `pre_install_script` for faster startup (e.g., `npm install -g @modelcontextprotocol/server-filesystem`)

### Direct Token Authentication

Use this example when you want to provide a GitHub Personal Access Token instead of using Coder external auth:

```tf
variable "github_token" {
  type        = string
  description = "GitHub Personal Access Token"
  sensitive   = true
}

module "copilot_cli" {
  source       = "registry.coder.com/coder-labs/copilot-cli/coder"
  version      = "0.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder/project"
  github_token = var.github_token
}
```

### Standalone Mode

Run Copilot CLI as a command-line tool without task reporting or web interface. This installs and configures Copilot CLI, making it available as a CLI app in the Coder agent bar that you can launch to interact with Copilot CLI directly from your terminal. Set `report_tasks = false` to disable integration with Coder Tasks.

```tf
module "copilot_cli" {
  source       = "registry.coder.com/coder-labs/copilot-cli/coder"
  version      = "0.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  report_tasks = false
  cli_app      = true
}
```

## Authentication

The module supports multiple authentication methods (in priority order):

1. **[Coder External Auth](https://coder.com/docs/admin/external-auth) (Recommended)** - Automatic if GitHub external auth is configured in Coder
2. **Direct Token** - Pass `github_token` variable (OAuth or Personal Access Token)
3. **Interactive** - Copilot CLI prompts for login via `/login` command if no auth found

> [!NOTE]
> OAuth tokens work best with Copilot CLI. Personal Access Tokens may have limited functionality.

## Session Resumption

By default, the module resumes the latest Copilot CLI session when the workspace restarts. Set `resume_session = false` to always start fresh sessions.

> [!NOTE]
> Session resumption requires persistent storage for the home directory or workspace volume. Without persistent storage, sessions will not resume across workspace restarts.

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
