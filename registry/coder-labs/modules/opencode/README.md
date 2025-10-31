---
display_name: OpenCode
icon: ../../../../.icons/opencode.svg
description: Run OpenCode AI coding assistant for AI-powered terminal assistance
verified: false
tags: [agent, opencode, ai, tasks]
---

# OpenCode

Run [OpenCode](https://opencode.ai) AI coding assistant in your workspace for intelligent code generation, analysis, and development assistance. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for seamless task reporting in the Coder UI.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}
```

## Prerequisites

- **Authentication credentials** - OpenCode auth.json file is required for non-interactive authentication, you can find this file on your system: `$HOME/.local/share/opencode/auth.json`

## Examples

### Basic Usage with Tasks

```tf
resource "coder_ai_task" "task" {
  app_id = module.opencode.task_app_id
}

module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  ai_prompt = coder_ai_task.task.prompt

  auth_json = <<-EOT
{
  "google": {
    "type": "api",
    "key": "gem-xxx-xxxx"
  },
  "anthropic": {
    "type": "api",
    "key": "sk-ant-api03-xxx-xxxxxxx"
  }
}
EOT

  config_json = jsonencode({
    "$schema" = "https://opencode.ai/config.json"
    mcp = {
      filesystem = {
        command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/home/coder/projects"]
        enabled = true
        type    = "local"
        environment = {
          SOME_VARIABLE_X = "value"
        }
      }
      playwright = {
        command = ["npx", "-y", "@playwright/mcp@latest", "--headless", "--isolated"]
        enabled = true
        type    = "local"
      }
    }
    model = "anthropic/claude-sonnet-4-20250514"
  })

  pre_install_script = <<-EOT
    #!/bin/bash
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  EOT
}
```

### Standalone CLI Mode

Run OpenCode as a command-line tool without web interface or task reporting:

```tf
module "opencode" {
  source       = "registry.coder.com/coder-labs/opencode/coder"
  version      = "0.1.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder"
  report_tasks = false
  cli_app      = true
}
```

## Troubleshooting

If you encounter any issues, check the log files in the `~/.opencode-module` directory within your workspace for detailed information.

## References

- [Opencode JSON Config](https://opencode.ai/docs/config/)
- [OpenCode Documentation](https://opencode.ai/docs)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
