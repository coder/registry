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
  - Coder external authentication (recommended)
  - GitHub CLI (`gh auth login`)
  - Environment token (`GITHUB_TOKEN`)
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
      github = {
        command = "@github/copilot-mcp-github"
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

This module works with multiple GitHub authentication methods:

**Recommended (automatic):**
- **Coder External Auth**: Configure GitHub external authentication in Coder for seamless OAuth token integration
- **GitHub CLI**: Users can run `gh auth login` in their workspace

**Automatic fallback:**
- **Environment tokens**: Uses existing `GITHUB_TOKEN` if available (note: Personal Access Tokens may not work with all Copilot CLI features)
- **Interactive login**: If no authentication is found, Copilot CLI will prompt users to login via the `/login` slash command

**No setup required** - the module automatically detects and uses whatever authentication is available.

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
