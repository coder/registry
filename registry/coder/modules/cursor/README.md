---
display_name: Cursor
description: Run Cursor IDE and CLI in your workspace
icon: ../../../../.icons/cursor.svg
verified: true
tags: [ide, cursor, ai, cli, agent]
---

# Cursor

Run [Cursor IDE](https://cursor.com) and [Cursor CLI](https://docs.cursor.com/en/cli/overview) in your workspace. Provides both desktop IDE integration and terminal-based AI coding assistance.

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "2.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template

## Features

- **Desktop IDE**: One-click button to launch Cursor IDE (uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder))
- **CLI Agent**: Terminal-based AI coding assistant with interactive and non-interactive modes
- **AgentAPI Integration**: Web interface for CLI interactions
- **Interactive Mode**: Conversational sessions with text output
- **Non-Interactive Mode**: Automation-friendly for scripts and CI pipelines

## Examples

### Basic setup with CLI enabled

```tf
module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

module "cursor" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/cursor/coder"
  version            = "2.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/project"
  install_cursor_cli = true
  install_agentapi   = true
}
```

### Desktop IDE only (legacy mode)

```tf
module "cursor" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/cursor/coder"
  version            = "2.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/project"
  install_cursor_cli = false
  install_agentapi   = false
}
```

### With custom pre-install script

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "2.0.0"
  agent_id = coder_agent.example.id
  
  pre_install_script = <<-EOT
    # Install additional dependencies
    npm install -g typescript
  EOT
}
```

## Usage

### Desktop IDE

Click the "Cursor Desktop" button in your workspace to launch Cursor IDE.

### CLI Agent

#### Web Interface

1. Click the "Cursor" button to access the web interface
2. Start interactive sessions with text output

#### Terminal Usage

```bash
# Interactive mode (default)
cursor-agent

# Interactive mode with initial prompt
cursor-agent "refactor the auth module to use JWT tokens"

# Non-interactive mode with text output
cursor-agent -p "find and fix performance issues" --output-format text

# Use specific model
cursor-agent -p "add error handling" --model "gpt-5"

# Session management
cursor-agent ls                 # List all previous chats
cursor-agent resume             # Resume latest conversation
cursor-agent --resume="chat-id" # Resume specific conversation
```

#### Interactive Mode Features

- Conversational sessions with the agent
- Review proposed changes before applying
- Real-time guidance and steering
- Text-based output optimized for terminal use
- Session persistence and resumption

#### Non-Interactive Mode Features

- Automation-friendly for scripts and CI pipelines
- Direct prompt execution with text output
- Model selection support
- Git integration for change reviews

## Configuration

The module supports the same configuration options as the Cursor CLI:

- **MCP (Model Context Protocol)**: Automatically detects `mcp.json` configuration
- **Rules System**: Supports `.cursor/rules` directory for custom agent behavior
- **Environment Variables**: Respects Cursor CLI environment settings

## Troubleshooting

The module creates log files in the workspace's `~/.cursor-module` directory. Check these files if you encounter issues:

```bash
# Check installation logs
cat ~/.cursor-module/install.log

# Check runtime logs
cat ~/.cursor-module/runtime.log

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
