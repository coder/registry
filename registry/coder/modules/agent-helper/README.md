---
display_name: AgentAPI
description: Building block for modules that need to run an AgentAPI server
icon: ../../../../.icons/coder.svg
verified: true
tags: [internal, library]
---

# AgentAPI

> [!CAUTION]
> We do not recommend using this module directly. Instead, please consider using one of our [Tasks-compatible AI agent modules](https://registry.coder.com/modules?search=tag%3Atasks).

The AgentAPI module is a building block for modules that need to run an AgentAPI server. It is intended primarily for internal use by Coder to create modules compatible with Tasks.

```tf
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "4.0.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "ClaudeCode"
  cli_app_slug         = "claude-cli"
  cli_app_display_name = "Claude CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_server_type = "claude"
  agentapi_term_width  = 67
  agentapi_term_height = 1190
}
```

## Task log snapshot

Captures the last 10 messages from AgentAPI when a task workspace stops. This allows viewing conversation history while the task is paused.

To enable for task workspaces:

```tf
module "agentapi" {
  # ... other config
  task_log_snapshot = true # default: true
}
```

## For module developers

For a complete example of how to use this module, see the [Goose module](https://github.com/coder/registry/blob/main/registry/coder/modules/goose/main.tf).

### agent-command.sh

The calling module must create an executable script at `$HOME/{module_dir_name}/agent-command.sh` before this module's script runs. This script should contain the command to start your AI agent.

Example:

```bash
#!/bin/bash
module_path="$HOME/.my-module"

cat > "$module_path/agent-command.sh" << EOF
#!/bin/bash
my-agent-command --my-agent-flags
EOF
```

The AgentAPI module will run this script with the agentapi server.
