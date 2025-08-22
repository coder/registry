---
display_name: Auggie CLI
icon: ../../../../.icons/auggie.svg
description: Run Auggie CLI in your workspace for AI-powered coding assistance with AgentAPI integration
verified: true
tags: [agent, auggie, ai, tasks, augment]
---

# Auggie CLI

Run Auggie CLI in your workspace to access Augment's AI coding assistant with advanced context understanding and codebase integration. This module integrates with [AgentAPI](https://github.com/coder/agentapi).

```tf
module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

## Prerequisites

- **Node.js and npm must be sourced/available before the auggie module installs** - ensure they are installed in your workspace image or via earlier provisioning steps
- You must add the [Coder Login](https://registry.coder.com/modules/coder/coder-login) module to your template
- **Augment session token for authentication (required for tasks). [Instructions](https://docs.augmentcode.com/cli/setup-auggie/authentication) to get the session token**

## Examples

### Usage with Tasks and Configuration

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial task prompt for Auggie CLI"
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}

module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  # Authentication
  augment_session_token = <<-EOF
  {"accessToken":"xxxx-yyyy-zzzz-jjjj","tenantURL":"https://d1.api.augmentcode.com/","scopes":["read","write"]}
EOF  # Required for tasks

  # Version
   auggie_version = "0.3.0"

  # Task configuration
  ai_prompt                      = data.coder_parameter.ai_prompt.value
  continue_previous_conversation = true
  interaction_mode               = "quiet"
  auggie_model                   = "gpt5"
  report_tasks                   = true

  # MCP configuration for additional integrations
  mcp = <<-EOF
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/coder/project"]
    }
  }
}
EOF

  # Workspace guidelines
  rules = <<-EOT
    # Project Guidelines

    ## Code Style
    - Use TypeScript for all new JavaScript files
    - Follow consistent naming conventions
    - Add comprehensive comments for complex logic

    ## Testing
    - Write unit tests for all new functions
    - Ensure test coverage above 80%

    ## Documentation
    - Update README.md for any new features
    - Document API changes in CHANGELOG.md
  EOT
}
```

### Using Multiple MCP Configuration Files

```tf
module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  # Multiple MCP configuration files
  mcp_files = [
    "/path/to/filesystem-mcp.json",
    "/path/to/database-mcp.json",
    "/path/to/api-mcp.json"
  ]

  mcp = <<-EOF
  {
  "mcpServers": {
    "Test MCP": {
      "command": "uv",
      "args": [
        "--directory",
        "/home/coder/test-mcp",
        "run",
        "server.py"
      ],
      "timeout": 600
    }
  }
}
EOF
}
```

### Troubleshooting

If you have any issues, please take a look at the log files below.

```bash
# Installation logs
cat ~/.auggie-module/install.log

# Startup logs
cat ~/.auggie-module/agentapi-start.log

# Pre/post install script logs
cat ~/.auggie-module/pre_install.log
cat ~/.auggie-module/post_install.log
```

> [!NOTE]
> To use tasks with Auggie CLI, create a `coder_parameter` named `"AI Prompt"` and pass its value to the auggie module's `ai_prompt` variable. The `folder` variable is required for the module to function correctly.

## References

- [Auggie CLI Reference](https://docs.augmentcode.com/cli/reference)
- [Auggie CLI MCP Integration](https://docs.augmentcode.com/cli/integrations#mcp-integrations)
- [Augment Code Documentation](https://docs.augmentcode.com/)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
