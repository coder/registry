---
display_name: Copilot CLI
description: GitHub Copilot CLI agent for AI-powered terminal assistance
icon: ../../../../.icons/github.svg
verified: false
tags: [agent, copilot, ai, github, tasks]
---

# Copilot

Run [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) in your workspace for AI-powered coding assistance directly from the terminal. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for task reporting in the Coder UI.

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "0.2.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/projects"
}
```

> [!IMPORTANT]
> This example assumes you have [Coder external authentication](https://coder.com/docs/admin/external-auth) configured with `id = "github"`. If not, you can provide a direct token using the `github_token` variable or provide the correct external authentication id for GitHub by setting `external_auth_id = "my-github"`.

> [!NOTE]
> By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

## Prerequisites

- **Node.js v22+** and **npm v10+**
- **[Active Copilot subscription](https://docs.github.com/en/copilot/about-github-copilot/subscription-plans-for-github-copilot)** (GitHub Copilot Pro, Pro+, Business, or Enterprise)
- **GitHub authentication** via one of:
  - [Coder external authentication](https://coder.com/docs/admin/external-auth) (recommended)
  - Direct token via `github_token` variable
  - Interactive login in Copilot

## Examples

### Usage with Tasks

For development environments where you want Copilot to have full access to tools and automatically resume sessions:

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial task prompt for Copilot."
  mutable     = true
}

module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "0.2.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/projects"

  ai_prompt       = data.coder_parameter.ai_prompt.value
  copilot_model   = "claude-sonnet-4.5"
  allow_all_tools = true
  resume_session  = true

  trusted_directories = ["/home/coder/projects", "/tmp"]
}
```

### Advanced Configuration

Customize tool permissions, MCP servers, and Copilot settings:

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "0.2.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/projects"

  # Version pinning (defaults to "0.0.334", use "latest" for newest version)
  copilot_version = "latest"

  # Tool permissions
  allow_tools         = ["shell(git)", "shell(npm)", "write"]
  trusted_directories = ["/home/coder/projects", "/tmp"]

  # Custom Copilot configuration
  copilot_config = jsonencode({
    banner = "never"
    theme  = "dark"
  })

  # MCP server configuration
  mcp_config = jsonencode({
    mcpServers = {
      filesystem = {
        command     = "npx"
        args        = ["-y", "@modelcontextprotocol/server-filesystem", "/home/coder/projects"]
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

module "copilot" {
  source       = "registry.coder.com/coder-labs/copilot/coder"
  version      = "0.2.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder/projects"
  github_token = var.github_token
}
```

### Standalone Mode

Run Copilot as a command-line tool without task reporting or web interface. This installs and configures Copilot, making it available as a CLI app in the Coder agent bar that you can launch to interact with Copilot directly from your terminal. Set `report_tasks = false` to disable integration with Coder Tasks.

```tf
module "copilot" {
  source       = "registry.coder.com/coder-labs/copilot/coder"
  version      = "0.2.0"
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
3. **Interactive** - Copilot prompts for login via `/login` command if no auth found

> [!NOTE]
> OAuth tokens work best with Copilot. Personal Access Tokens may have limited functionality.

## Session Resumption

By default, the module resumes the latest Copilot session when the workspace restarts. Set `resume_session = false` to always start fresh sessions.

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
> To use tasks with Copilot, you must have an active GitHub Copilot subscription.
> The `workdir` variable is required and specifies the directory where Copilot will run.

## References

- [GitHub Copilot CLI Documentation](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli)
- [Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
