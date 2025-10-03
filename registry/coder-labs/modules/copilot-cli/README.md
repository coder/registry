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
  - Direct token via `github_token` variable
  - [Coder external authentication](https://coder.com/docs/admin/external-auth) (recommended)
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

### Advanced Configuration with Specific Tool Permissions

For more controlled environments where you want to specify exact tools:

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  allow_tools         = ["shell(git)", "shell(npm)", "write"]
  trusted_directories = ["/home/coder/workspace", "/tmp"]

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

Run and configure Copilot CLI as a standalone tool in your workspace.

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

### Custom Configuration

You can customize the entire Copilot CLI configuration:

```tf
module "copilot_cli" {
  source   = "registry.coder.com/coder-labs/copilot-cli/coder"
  version  = "0.1.0"
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

## Authentication

The module supports multiple authentication methods (in priority order):

1. **Direct Token** - Pass `github_token` variable (OAuth or Personal Access Token)
2. **Coder External Auth** - Automatic if GitHub external auth is configured in Coder
3. **Interactive** - Copilot CLI prompts for login via `/login` command if no auth found

> [!NOTE]
> OAuth tokens work best with Copilot CLI. Personal Access Tokens may have limited functionality.

## Session Resumption

By default, the module resumes the latest Copilot CLI session when the workspace restarts. Set `resume_session = false` to always start fresh sessions.

## Task Reporting

When enabled (default), Copilot CLI can report task progress to the Coder UI using [AgentAPI](https://github.com/coder/agentapi). Custom MCP servers provided via `mcp_config` are merged with the Coder MCP server automatically.

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
