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
  version = "2.4.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Goose"
  cli_app_slug         = "goose-cli"
  cli_app_display_name = "Goose CLI"
  module_directory     = local.module_directory
  install_agentapi     = var.install_agentapi
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

## State Persistence

AgentAPI can save and restore conversation state across workspace restarts.
This is disabled by default and requires agentapi binary >= v0.12.0.

State and PID files are stored in the `module_directory` alongside other module files (e.g. `$HOME/.coder-modules/coder/claude-code/agentapi-state.json`).

To enable:

```tf
module "agentapi" {
  # ... other config
  enable_state_persistence = true
}
```

To override file paths:

```tf
module "agentapi" {
  # ... other config
  state_file_path = "/custom/path/state.json"
  pid_file_path   = "/custom/path/agentapi.pid"
}
```

## For module developers

For a complete example of how to use this module, see the [Goose module](https://github.com/coder/registry/blob/main/registry/coder/modules/goose/main.tf).
