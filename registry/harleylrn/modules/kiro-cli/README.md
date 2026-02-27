---
display_name: Kiro CLI
description: Run Kiro CLI in your workspace to access AI coding assistant with MCP integration and task reporting.
icon: ../../../../.icons/kiro.svg
verified: true
tags: [agent, ai, kiro, kiro-cli, tasks]
---

# Kiro CLI

Run [Kiro CLI](https://kiro.dev/) in your workspace to access AI coding assistant. This module provides a complete integration with Coder workspaces, including automatic installation, MCP (Model Context Protocol) integration for task reporting, and support for custom pre/post install scripts.

```tf
module "kiro-cli" {
  source   = "registry.coder.com/harleylrn/kiro-cli/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder"

  # Required: Authentication tarball (see below for generation)
  auth_tarball = <<-EOF
base64encoded-tarball
EOF
}
```

![Kiro CLI in action](../../.images/kiro-cli.png)

## Prerequisites

- **zstd** - Required for compressing the authentication tarball
  - **Ubuntu/Debian**: `sudo apt-get install zstd`
  - **RHEL/CentOS/Fedora**: `sudo yum install zstd` or `sudo dnf install zstd`
- **auth_tarball** - Required for installation and authentication

### Authentication Tarball

You must generate an authenticated Kiro CLI tarball on another machine where you have successfully logged in:

```bash
# 1. Install Kiro CLI and login on your local machine
kiro-cli login

# 2. Generate the authentication tarball
cd ~/.local/share/kiro-cli
tar -c . | zstd | base64 -w 0
```

Copy the output and use it as the `auth_tarball` variable.

## Detailed Authentication Setup

**Step 1: Install Kiro CLI locally**

- Download from [Kiro CLI](https://kiro.dev/)
- Follow the installation instructions for your platform

**Step 2: Authenticate**

```bash
kiro-cli login
```

Complete the authentication process in your browser.

**Step 3: Generate tarball**

```bash
cd ~/.local/share/kiro-cli
tar -c . | zstd | base64 -w 0 > /tmp/kiro-cli-auth.txt
```

**Step 4: Use in Terraform**

```tf
variable "kiro_cli_auth_tarball" {
  type      = string
  sensitive = true
  default   = "PASTE_YOUR_TARBALL_HERE"
}
```

> [!IMPORTANT]
>
> - Regenerate the tarball if you logout or re-authenticate
> - Each user needs their own authentication tarball
> - Keep the tarball secure as it contains authentication credentials

### Coder Tasks Integration

To enable integration with [Coder Tasks](https://coder.com/docs/ai-coder/tasks), you need to define the `coder_task` data source, create the `coder_ai_task` resource, and configure the module with the task prompt.

```tf
data "coder_task" "me" {}

module "kiro-cli" {
  count           = data.coder_task.me.enabled ? data.coder_workspace.me.start_count : 0
  source          = "registry.coder.com/harleylrn/kiro-cli/coder"
  version         = "1.1.0"
  agent_id        = coder_agent.example.id
  workdir         = "/home/coder"
  auth_tarball    = var.kiro_cli_auth_tarball
  ai_prompt       = data.coder_task.me.prompt
  trust_all_tools = true

  # Task reporting configuration
  report_tasks = true

  # Enable CLI app alongside web app
  cli_app              = true
  web_app_display_name = "Kiro CLI"
  cli_app_display_name = "Kiro CLI"
}

resource "coder_ai_task" "task" {
  count  = data.coder_task.me.enabled ? data.coder_workspace.me.start_count : 0
  app_id = module.kiro-cli[count.index].task_app_id
}
```

> [!IMPORTANT]
>
> - The `data "coder_task" "me" {}` data source provides the task prompt and enabled state
> - The module count is controlled by `data.coder_task.me.enabled` to only create when a task is active
> - The `coder_ai_task` resource links the module's task reporting to Coder's task system
> - The `ai_prompt` is passed from `data.coder_task.me.prompt`
> - Without this configuration, `coder_ai_task` resources will not function properly
>
> **_Security Notice_**
> In order to allow the tasks flow non-interactively all the tools are trusted
> This flag bypasses standard permission checks and allows Kiro CLI broader access to your system than normally permitted.
> While this enables more functionality, it also means Kiro CLI can potentially execute commands with the same privileges as the user running it.
> Use this module only in trusted environments and be aware of the security implications.

### Default System Prompt

The module includes a simple system prompt that instructs Kiro CLI:

```
You are a helpful Coding assistant. Aim to autonomously investigate
and solve issues the user gives you and test your work, whenever possible.
Avoid shortcuts like mocking tests. When you get stuck, you can ask the user
but opt for autonomy.
```

You can customize this behavior by providing your own system prompt via the `system_prompt` variable.

### Default Coder MCP Instructions

The module includes specific instructions for the Coder MCP server integration that are separate from the system prompt:

```
YOU MUST REPORT ALL TASKS TO CODER.
When reporting tasks you MUST follow these EXACT instructions:
- IMMEDIATELY report status after receiving ANY user message
- Be granular If you are investigating with multiple steps report each step to coder.

Task state MUST be one of the following:
- Use "state": "working" when actively processing WITHOUT needing additional user input
- Use "state": "complete" only when finished with a task
- Use "state": "failure" when you need ANY user input lack sufficient details or encounter blockers.

Task summaries MUST:
- Include specifics about what you're doing
- Include clear and actionable steps for the user
- Be less than 160 characters in length
```

You can customize these instructions by providing your own via the `coder_mcp_instructions` variable.

## Default Agent Configuration

The module includes a default agent configuration template that provides a comprehensive setup for Kiro CLI integration:

```json
{
  "name": "agent",
  "description": "This is an default agent config",
  "prompt": "${system_prompt}",
  "mcpServers": {},
  "tools": ["read", "write", "shell", "aws", "@coder", "knowledge"],
  "toolAliases": {},
  "allowedTools": ["read", "@coder"],
  "resources": [
    "file://KiroQ.md",
    "file://README.md",
    "file://.kiro/steering/**/*.md"
  ],
  "hooks": {},
  "toolsSettings": {},
  "useLegacyMcpJson": true
}
```

### Configuration Details:

- **Tools Available:** File operations (`read`, `write`), shell execution (`shell`), AWS CLI (`aws`), Coder MCP integration (`@coder`), and knowledge base access (`knowledge`)
- **@coder Tool:** Enables Coder MCP integration for task reporting (`coder_report_task` and related tools)
- **Allowed Tools:** By default, only `read` and `@coder` are allowed (can be customized for security)
- **Resources:** Access to documentation and rule files in the workspace
- **MCP Servers:** Empty by default, can be configured via `agent_config` variable
- **System Prompt:** Dynamically populated from the `system_prompt` variable
- **Legacy MCP:** Uses legacy MCP JSON format for compatibility

You can override this configuration by providing your own JSON via the `agent_config` variable.

### Agent Name Configuration

The module automatically extracts the agent name from the `"name"` field in the `agent_config` JSON and uses it for:

- **Configuration File:** Saves the agent config as `~/.kiro/agents/{agent_name}.json`
- **Default Agent:** Sets the agent as the default using `q settings chat.defaultAgent {agent_name}`
- **MCP Integration:** Associates the Coder MCP server with the specified agent name

If no custom `agent_config` is provided, the default agent name "agent" is used.

## Usage Examples

### Basic Usage

```tf
module "kiro-cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  auth_tarball = var.kiro_cli_auth_tarball
}
```

This example will:

1. Download and install Kiro CLI latest version
2. Extract authentication tarball to ~/.local/share/kiro-cli
3. Configure Coder MCP integration for task reporting
4. Create default agent configuration file
5. Start Kiro CLI in /home/coder directory
6. Provide web interface through AgentAPI

> [!IMPORTANT]
> By default `write` tool is not allowed, which will pause the task execution
> and will wait for the prompt to approve its usage.
> To avoid this, and allow the normal task flow, user has two options:
>
> - Change the parameter `trust_all_tools` value to `true` (default to `false`)
>   OR
> - Provide your own agent configuration with the tools of your choice allowed

### With Custom AI Prompt

```tf
module "kiro-cli" {
  source          = "registry.coder.com/harleylrn/kiro-cli/coder"
  version         = "1.1.0"
  agent_id        = coder_agent.example.id
  workdir         = "/home/coder"
  auth_tarball    = var.kiro_cli_auth_tarball
  ai_prompt       = "Help me set up a Python FastAPI project with proper testing structure"
  trust_all_tools = true
}
```

> [!IMPORTANT]
> **_Security Notice_**
> In order to allow the tasks flow non-interactively all the tools are trusted
> This flag bypasses standard permission checks and allows Kiro CLI broader access to your system than normally permitted.
> While this enables more functionality, it also means Kiro CLI can potentially execute commands with the same privileges as the user running it.
> Use this module only in trusted environments and be aware of the security implications.

### With Custom Pre/Post Install Scripts

```tf
module "kiro-cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  auth_tarball = var.kiro_cli_auth_tarball

  pre_install_script = <<-EOT
    #!/bin/bash
    echo "Setting up custom environment..."
    # Install additional dependencies
    sudo apt-get update && sudo apt-get install -y zstd
  EOT

  post_install_script = <<-EOT
    #!/bin/bash
    echo "Configuring Kiro CLI settings..."
    # Custom configuration commands
    kiro-cli settings chat.model claude-3-sonnet
  EOT
}
```

### Specific Version Installation

```tf
module "kiro-cli" {
  source           = "registry.coder.com/harleylrn/kiro-cli/coder"
  version          = "1.1.0"
  agent_id         = coder_agent.example.id
  workdir          = "/home/coder"
  auth_tarball     = var.kiro_cli_auth_tarball
  kiro_cli_version = "1.14.0" # Specific version
  install_kiro_cli = true
}
```

### Custom Agent Configuration

```tf
module "kiro-cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  auth_tarball = var.kiro_cli_auth_tarball

  agent_config = <<-EOT
    {
      "name": "custom-agent",
      "description": "Custom Kiro CLI agent for my workspace",
      "prompt": "You are a specialized DevOps assistant...",
      "tools": ["read", "write", "shell", "aws"]
    }
  EOT
}
```

### With Custom AgentAPI Configuration

```tf
module "kiro-cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  auth_tarball = var.kiro_cli_auth_tarball

  # AgentAPI configuration for environments without wildcard access url. https://coder.com/docs/admin/setup#wildcard-access-url
  agentapi_chat_based_path = true
  agentapi_version         = "v0.10.0"
}
```

### Air-Gapped Installation

For environments without direct internet access, you can host Kiro CLI installation files internally and configure the module to use your internal repository:

```tf
module "kiro-cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  auth_tarball = var.kiro_cli_auth_tarball

  # Point to internal artifact repository
  kiro_install_url = "https://artifacts.internal.corp/kiro-cli-releases"

  # Use specific version available in your repository
  kiro_cli_version = "latest"
}
```

**Prerequisites for Air-Gapped Setup:**

1. Download Kiro CLI installation files from the official source and host them internally
2. Maintain the same directory structure: `{base_url}/{version}/kirocli-{arch}-linux.zip`
3. Ensure both architectures are available:
   - `kirocli-x86_64-linux.zip` for Intel/AMD systems
   - `kirocli-aarch64-linux.zip` for ARM systems
4. Configure network access from Coder workspaces to your internal repository

## Troubleshooting

### Common Issues

**Authentication issues:**

- Regenerate the auth tarball on your local machine
- Ensure the tarball is properly base64 encoded
- Check that the original authentication is still valid

**MCP integration not working:**

- Verify that AgentAPI is installed (`install_agentapi = true`)
- Check that the Coder agent is properly configured
- Review the system prompt configuration

## Outputs

| Name                                                                 | Description |
| -------------------------------------------------------------------- | ----------- |
| <a name="output_task_app_id"></a> [task_app_id](#output_task_app_id) | n/a         |
