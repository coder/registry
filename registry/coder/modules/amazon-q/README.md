---
display_name: Amazon Q
description: Run Amazon Q in your workspace to access Amazon's AI coding assistant with MCP integration and task reporting.
icon: ../../../../.icons/amazon-q.svg
verified: true
tags: [agent, ai, aws, amazon-q, mcp, agentapi]
---

# Amazon Q

Run [Amazon Q](https://aws.amazon.com/q/) in your workspace to access Amazon's AI coding assistant. This module provides a complete integration with Coder workspaces, including automatic installation, MCP (Model Context Protocol) integration for task reporting, and support for custom pre/post install scripts.

```tf
module "amazon-q" {
  source   = "registry.coder.com/coder/amazon-q/coder"
  version  = "2.0.0"
  agent_id = coder_agent.example.id

  # Required: Authentication tarball (see below for generation)
  auth_tarball = var.amazon_q_auth_tarball
}
```

![Amazon-Q in action](../../.images/amazon-q-new.png)

## Features

- **🚀 Automatic Installation**: Downloads and installs Amazon Q CLI automatically
- **🔐 Authentication**: Supports pre-authenticated tarball for seamless login
- **📊 Task Reporting**: Built-in MCP integration for reporting progress to Coder
- **🎯 AI Prompts**: Support for initial task prompts and custom system prompts
- **🔧 Customization**: Pre/post install scripts for custom setup
- **🌐 AgentAPI Integration**: Web and CLI app integration through AgentAPI
- **🛠️ Tool Trust**: Configurable tool trust settings
- **📁 Flexible Deployment**: Configurable working directory and module structure

## Dependencies

This module has critical dependencies on AgentAPI components for proper web integration and interactive functionality:

### AgentAPI Coder Module

- **Module**: `registry.coder.com/coder/agentapi/coder`
- **Version**: `1.1.1` (hardcoded in module)
- **Purpose**: Provides the Coder module infrastructure for AgentAPI integration
- **Functionality**: Handles module lifecycle, configuration, and Coder-specific integration

### AgentAPI Binary

- **Binary Version**: `v0.6.0` (configurable via `agentapi_version` parameter)
- **Installation**: Automatically downloaded and installed when `install_agentapi = true`
- **Purpose**: The actual AgentAPI server binary that runs the web interface
- **Functionality**: Provides the runtime server for web-based interactions

**Why Both Components are Required:**

- **Coder Module (1.1.1)**: Integrates AgentAPI into the Coder ecosystem and manages the module lifecycle
- **AgentAPI Binary (v0.6.0)**: Provides the actual web interface and interactive functionality
- **Web Interface**: Enables web-based chat interface accessible through Coder
- **Session Management**: Handles interactive sessions and maintains state
- **MCP Protocol**: Facilitates Model Context Protocol communication for task reporting
- **Real-time Updates**: Enables live progress reporting through the `coder_report_task` tool

**Version Compatibility:**

- **Module Version**: Fixed at `1.1.1` for stability and compatibility
- **Binary Version**: Configurable (default `v0.6.0`) to allow updates and customization
- **Coder Integration**: Ensure your Coder deployment supports both component versions
- **Upgrade Path**: Binary version can be updated via `agentapi_version` parameter

## Prerequisites

### Authentication Tarball (Required)

You must generate an authenticated Amazon Q tarball on another machine where you have successfully logged in:

```bash
# 1. Install Amazon Q and login on your local machine
q login

# 2. Generate the authentication tarball
cd ~/.local/share/amazon-q
tar -c . | zstd | base64 -w 0
```

Copy the output and use it as the `auth_tarball` variable.

<details>
<summary><strong>Detailed Authentication Setup</strong></summary>

**Step 1: Install Amazon Q locally**

- Download from [AWS Amazon Q Developer](https://aws.amazon.com/q/developer/)
- Follow the installation instructions for your platform

**Step 2: Authenticate**

```bash
q login
```

Complete the authentication process in your browser.

**Step 3: Generate tarball**

```bash
cd ~/.local/share/amazon-q
tar -c . | zstd | base64 -w 0 > /tmp/amazon-q-auth.txt
```

**Step 4: Use in Terraform**

```tf
variable "amazon_q_auth_tarball" {
  type      = string
  sensitive = true
  default   = "PASTE_YOUR_TARBALL_HERE"
}
```

**Important Notes:**

- Regenerate the tarball if you logout or re-authenticate
- Each user needs their own authentication tarball
- Keep the tarball secure as it contains authentication credentials

</details>

## Configuration Variables

### Required Variables

| Variable   | Type     | Description             |
| ---------- | -------- | ----------------------- |
| `agent_id` | `string` | The ID of a Coder agent |

### Optional Variables

| Variable              | Type     | Default                                               | Description                                                                                                                                                           |
| --------------------- | -------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auth_tarball`        | `string` | `""`                                                  | Base64 encoded, zstd compressed tarball of authenticated Amazon Q directory                                                                                           |
| `amazon_q_version`    | `string` | `"1.14.1"`                                            | Version of Amazon Q to install                                                                                                                                        |
| `q_install_url`       | `string` | `"https://desktop-release.q.us-east-1.amazonaws.com"` | Base URL for Amazon Q installation downloads                                                                                                                          |
| `install_amazon_q`    | `bool`   | `true`                                                | Whether to install Amazon Q CLI                                                                                                                                       |
| `install_agentapi`    | `bool`   | `true`                                                | Whether to install AgentAPI for web integration                                                                                                                       |
| `agentapi_version`    | `string` | `"v0.6.0"`                                            | Version of AgentAPI to install                                                                                                                                        |
| `trust_all_tools`     | `bool`   | `false`                                               | Whether to trust all tools in Amazon Q                                                                                                                                |
| `ai_prompt`           | `string` | `""`                                                  | Initial task prompt to send to Amazon Q                                                                                                                               |
| `system_prompt`       | `string` | _See below_                                           | System prompt for task reporting behavior                                                                                                                             |
| `pre_install_script`  | `string` | `null`                                                | Script to run before installing Amazon Q                                                                                                                              |
| `post_install_script` | `string` | `null`                                                | Script to run after installing Amazon Q                                                                                                                               |
| `agent_config`        | `string` | `null`                                                | Custom agent configuration JSON. The "name" field is used as the agent name and config filename (See the [Default Agent configuration](#default-agent-configuration)) |

### UI Configuration

| Variable | Type     | Default                | Description                                 |
| -------- | -------- | ---------------------- | ------------------------------------------- |
| `order`  | `number` | `null`                 | Position in UI (lower numbers appear first) |
| `group`  | `string` | `null`                 | Group name for organizing apps              |
| `icon`   | `string` | `"/icon/amazon-q.svg"` | Icon to display in UI                       |

### Default System Prompt

The module includes a comprehensive system prompt that instructs Amazon Q:

```
You are a helpful Coding assistant. Aim to autonomously investigate
and solve issues the user gives you and test your work, whenever possible.
Avoid shortcuts like mocking tests. When you get stuck, you can ask the user
but opt for autonomy.

YOU MUST REPORT ALL TASKS TO CODER.
When reporting tasks, you MUST follow these EXACT instructions:
- IMMEDIATELY report status after receiving ANY user message.
- Be granular. If you are investigating with multiple steps, report each step to coder.

Task state MUST be one of the following:
- Use "state": "working" when actively processing WITHOUT needing additional user input.
- Use "state": "complete" only when finished with a task.
- Use "state": "failure" when you need ANY user input, lack sufficient details, or encounter blockers.

Task summaries MUST:
- Include specifics about what you're doing.
- Include clear and actionable steps for the user.
- Be less than 160 characters in length.
```

### System Prompt Features:

- **Autonomous Operation:** Encourages Amazon Q to work independently and test solutions
- **Task Reporting:** Mandatory reporting to Coder via MCP integration
- **Granular Updates:** Step-by-step progress reporting for complex tasks
- **Clear State Management:** Three distinct states (working, complete, failure)
- **Concise Summaries:** 160-character limit for actionable task summaries
- **User Interaction:** Clear guidelines on when to ask for user input

You can customize this behavior by providing your own system prompt via the `system_prompt` variable.

## Default Agent Configuration

The module includes a default agent configuration template that provides a comprehensive setup for Amazon Q integration:

```json
{
  "name": "agent",
  "description": "This is an default agent config",
  "prompt": "${system_prompt}",
  "mcpServers": {},
  "tools": ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"],
  "toolAliases": {},
  "allowedTools": ["fs_read"],
  "resources": [
    "file://AmazonQ.md",
    "file://README.md",
    "file://.amazonq/rules/**/*.md"
  ],
  "hooks": {},
  "toolsSettings": {},
  "useLegacyMcpJson": true
}
```

### Configuration Details:

- **Tools Available:** File operations, bash execution, AWS CLI, and knowledge base access
- **Allowed Tools:** By default, only `fs_read` is allowed (can be customized)
- **Resources:** Access to documentation and rule files in the workspace
- **MCP Servers:** Empty by default, can be configured via `agent_config` variable
- **System Prompt:** Dynamically populated from the `system_prompt` variable

You can override this configuration by providing your own JSON via the `agent_config` variable.

### Agent Name Configuration

The module automatically extracts the agent name from the `"name"` field in the `agent_config` JSON and uses it for:

- **Configuration File:** Saves the agent config as `~/.aws/amazonq/cli-agents/{agent_name}.json`
- **Default Agent:** Sets the agent as the default using `q settings chat.defaultAgent {agent_name}`
- **MCP Integration:** Associates the Coder MCP server with the specified agent name

If no custom `agent_config` is provided, the default agent name "agent" is used.

## Usage Examples

### Basic Usage

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
}
```

### With Custom AI Prompt

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
  ai_prompt    = "Help me set up a Python FastAPI project with proper testing structure"
}
```

### With Custom Pre/Post Install Scripts

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball

  pre_install_script = <<-EOT
    #!/bin/bash
    echo "Setting up custom environment..."
    # Install additional dependencies
    sudo apt-get update && sudo apt-get install -y zstd
  EOT

  post_install_script = <<-EOT
    #!/bin/bash
    echo "Configuring Amazon Q settings..."
    # Custom configuration commands
    q settings chat.model claude-3-sonnet
  EOT
}
```

### Specific Version Installation

```tf
module "amazon-q" {
  source           = "registry.coder.com/coder/amazon-q/coder"
  version          = "2.0.0"
  agent_id         = coder_agent.example.id
  auth_tarball     = var.amazon_q_auth_tarball
  amazon_q_version = "1.14.0" # Specific version
  install_amazon_q = true
}
```

### Custom Agent Configuration

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball

  agent_config = jsonencode({
    name        = "custom-agent"
    description = "Custom Amazon Q agent for my workspace"
    prompt      = "You are a specialized DevOps assistant..."
    tools       = ["fs_read", "fs_write", "execute_bash", "use_aws"]
  })
}
```

### UI Customization

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball

  # UI configuration
  order = 1
  group = "AI Tools"
  icon  = "/icon/custom-amazon-q.svg"
}
```

### Air-Gapped Installation

For environments without direct internet access, you can host Amazon Q installation files internally and configure the module to use your internal repository:

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball

  # Point to internal artifact repository
  q_install_url = "https://artifacts.internal.corp/amazon-q-releases"

  # Use specific version available in your repository
  amazon_q_version = "1.14.1"
}
```

**Prerequisites for Air-Gapped Setup:**

1. Download Amazon Q installation files from AWS and host them internally
2. Maintain the same directory structure: `{base_url}/{version}/q-{arch}-linux.zip`
3. Ensure both architectures are available:
   - `q-x86_64-linux.zip` for Intel/AMD systems
   - `q-aarch64-linux.zip` for ARM systems
4. Configure network access from Coder workspaces to your internal repository

## Architecture

### Components

1. **AgentAPI Module**: Provides web and CLI app integration
2. **Install Script**: Handles Amazon Q CLI installation and configuration
3. **Start Script**: Manages Amazon Q startup with proper environment
4. **MCP Integration**: Enables task reporting back to Coder
5. **Agent Configuration**: Customizable AI agent behavior

### Installation Process

1. **Pre-install**: Execute custom pre-install script (if provided)
2. **Download**: Fetch Amazon Q CLI for the appropriate architecture
3. **Install**: Install Amazon Q CLI to `~/.local/bin/q`
4. **Authenticate**: Extract and apply authentication tarball
5. **Configure**: Set up MCP integration and agent configuration
6. **Post-install**: Execute custom post-install script (if provided)

### Runtime Behavior

- Amazon Q runs in the specified working directory
- MCP integration reports task progress to Coder
- AgentAPI provides web interface integration
- All tools are trusted by default (configurable)
- Initial AI prompt is sent if provided

## Troubleshooting

### Common Issues

**Amazon Q not found after installation:**

```bash
# Check if Amazon Q is in PATH
which q
# If not found, add to PATH
export PATH="$PATH:$HOME/.local/bin"
```

**Authentication issues:**

- Regenerate the auth tarball on your local machine
- Ensure the tarball is properly base64 encoded
- Check that the original authentication is still valid

**MCP integration not working:**

- Verify that AgentAPI is installed (`install_agentapi = true`)
- Check that the Coder agent is properly configured
- Review the system prompt configuration

### Debug Mode

Enable verbose logging by setting environment variables:

```bash
export DEBUG=1
export VERBOSE=1
```

## Security Considerations

- **Authentication Tarball**: Contains sensitive authentication data - mark as sensitive in Terraform
- **Tool Trust**: By default, all tools are trusted - review for security requirements
- **Pre/Post Scripts**: Custom scripts run with user permissions - validate content
- **Network Access**: Amazon Q requires internet access for AI model communication

## Contributing

For issues, feature requests, or contributions, please visit the [module repository](https://github.com/coder/registry).

## License

This module is provided under the same license as the Coder registry.

---

**Note**: This module requires Coder v2.7+ and is designed to work with the AgentAPI integration system.
