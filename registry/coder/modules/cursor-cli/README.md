---
display_name: Cursor CLI
description: Run Cursor CLI agent in your workspace with MCP and force mode support
icon: ../../../../.icons/cursor.svg
verified: true
tags: [cli, cursor, ai, agent, mcp, automation]
---

# Cursor CLI

Run the [Cursor CLI](https://docs.cursor.com/en/cli/overview) agent in your workspace for terminal-based AI coding assistance. Supports both interactive and non-interactive modes, MCP (Model Context Protocol), and automation features.

```tf
module "cursor-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template

## Features

- **CLI Agent**: Terminal-based AI coding assistant with interactive and non-interactive modes
- **AgentAPI Integration**: Web interface for CLI interactions
- **Interactive Mode**: Conversational sessions with text output
- **Non-Interactive Mode**: Automation-friendly for scripts and CI pipelines
- **Session Management**: List, resume, and manage coding sessions
- **Model Selection**: Support for multiple AI models (GPT-5, Claude, etc.)
- **MCP Support**: Model Context Protocol for extended functionality
- **Rules System**: Custom agent behavior configuration

## Examples

### Basic setup

```tf
module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

module "cursor-cli" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/cursor-cli/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/project"
  install_cursor_cli = true
  install_agentapi   = true
}
```

### CLI only (no web interface)

```tf
module "cursor-cli" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/cursor-cli/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/project"
  install_cursor_cli = true
  install_agentapi   = false
}
```

### With MCP and force mode for automation

```tf
module "cursor-cli" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/cursor-cli/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/project"
  
  # MCP Configuration
  enable_mcp         = true
  mcp_config_path    = "/home/coder/.cursor/custom-mcp.json"
  
  # Automation Features
  enable_force_mode  = true
  default_model      = "gpt-5"
  
  # Rules System
  enable_rules       = true
}
```

### Integration with Coder Tasks

```tf
# Cursor CLI module with automation features
module "cursor-cli" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/coder/cursor-cli/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  enable_force_mode = true
  default_model     = "claude-4-sonnet"
}

# Automated code review task
resource "coder_task" "ai_code_review" {
  agent_id = coder_agent.example.id
  name     = "AI Code Review"
  command  = "cursor-agent -p 'review the latest git changes for security issues and best practices' --force --output-format text"
  cron     = "0 9 * * 1-5"  # Weekdays at 9 AM
}

# Automated test generation
resource "coder_task" "generate_tests" {
  agent_id = coder_agent.example.id
  name     = "Generate Missing Tests"
  command  = "cursor-agent -p 'analyze the src/ directory and generate unit tests for functions missing test coverage' --force"
  cron     = "0 18 * * *"  # Daily at 6 PM
}

# Documentation updates
resource "coder_task" "update_docs" {
  agent_id = coder_agent.example.id
  name     = "Update Documentation"
  command  = "cursor-agent -p 'review and update README.md to reflect any new features or API changes' --force --model gpt-5"
  cron     = "0 12 * * 0"  # Sundays at noon
}
```

### With custom pre-install script

```tf
module "cursor-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  pre_install_script = <<-EOT
    # Install additional dependencies
    npm install -g typescript
  EOT
}
```

## Usage

### Web Interface

1. Click the "Cursor CLI" button to access the web interface
2. Start interactive sessions with text output

### Terminal Usage

```bash
# Interactive mode (default)
cursor-agent

# Interactive mode with initial prompt
cursor-agent "refactor the auth module to use JWT tokens"

# Non-interactive mode with text output
cursor-agent -p "find and fix performance issues" --output-format text

# Force mode for automation (non-interactive)
cursor-agent -p "review code for security issues" --force

# Use specific model
cursor-agent -p "add error handling" --model "gpt-5"

# Combine force mode with model selection
cursor-agent -p "generate comprehensive tests" --force --model "claude-4-sonnet"

# Session management
cursor-agent ls                 # List all previous chats
cursor-agent resume             # Resume latest conversation
cursor-agent --resume="chat-id" # Resume specific conversation
```

### Interactive Mode Features

- Conversational sessions with the agent
- Review proposed changes before applying
- Real-time guidance and steering
- Text-based output optimized for terminal use
- Session persistence and resumption

### Non-Interactive Mode Features

- Automation-friendly for scripts and CI pipelines
- Direct prompt execution with text output
- Model selection support
- Git integration for change reviews

## Screenshots

### Cursor CLI with Coder Tasks Integration

*Screenshot showing the cursor-cli module working with automated Coder Tasks will be added here*

- Interactive web interface for cursor-agent
- Automated code review tasks running in background
- Terminal output showing force mode execution
- MCP integration with custom tools

## Configuration

The module supports comprehensive configuration options:

### Core Features
- **MCP (Model Context Protocol)**: Automatically detects `mcp.json` configuration or uses custom path
- **Rules System**: Supports `.cursor/rules` directory for custom agent behavior
- **Force Mode**: Enable non-interactive automation for CI/CD pipelines
- **Model Selection**: Set default AI model (gpt-5, claude-4-sonnet, etc.)
- **Environment Variables**: Respects Cursor CLI environment settings

### Available Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_mcp` | bool | `true` | Enable MCP (Model Context Protocol) support |
| `mcp_config_path` | string | `""` | Path to custom MCP configuration file |
| `enable_force_mode` | bool | `false` | Enable force mode for non-interactive automation |
| `default_model` | string | `""` | Default AI model (e.g., gpt-5, claude-4-sonnet) |
| `enable_rules` | bool | `true` | Enable the rules system (.cursor/rules directory) |
| `install_cursor_cli` | bool | `true` | Whether to install Cursor CLI |
| `install_agentapi` | bool | `true` | Whether to install AgentAPI web interface |
| `folder` | string | `"/home/coder"` | Working directory for cursor-agent |

## Troubleshooting

The module creates log files in the workspace's `~/.cursor-cli-module` directory. Check these files if you encounter issues:

```bash
# Check installation logs
cat ~/.cursor-cli-module/install.log

# Check runtime logs
cat ~/.cursor-cli-module/runtime.log

# Verify Cursor CLI installation
cursor-agent --help
```

### Common Issues

1. **Cursor CLI not found**: Ensure `install_cursor_cli = true` or install manually:

   ```bash
   curl https://cursor.com/install -fsS | bash
   ```

2. **Permission issues**: Check that the installation script has proper permissions

3. **Path issues**: The module automatically adds Cursor CLI to PATH, but you may need to restart your shell
