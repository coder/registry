---
display_name: AgentAPI
description: Building block for modules that need to run an AgentAPI server.
icon: ../../../../.icons/coder.svg
verified: true
tags: [internal, library]
---

# AgentAPI

> [!CAUTION]
> We do not recommend using this module directly. Instead, please consider using one of our [Tasks-compatible AI agent modules](https://registry.coder.com/modules?search=tag%3Atasks).

The AgentAPI module is a building block for modules that need to run an [AgentAPI](https://github.com/coder/agentapi) server. It is intended primarily for internal use by Coder to create modules compatible with [Tasks](https://coder.com/docs/ai-coder/tasks).

```tf
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "2.5.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_icon         = var.icon
  web_app_display_name = "Goose"
  cli_app_display_name = "Goose CLI"
  cli_app_slug         = "goose-cli"
  module_directory     = local.module_directory
  install_agentapi     = var.install_agentapi
}
```

## Features

- **Web and CLI apps**: creates `coder_app` resources for browser-based chat and terminal attachment
- **Task log snapshot**: captures the last 10 conversation messages when a workspace stops, enabling offline viewing while the task is paused
- **State persistence**: optionally saves and restores AgentAPI conversation state across workspace restarts (requires agentapi >= v0.12.0)
- **Script orchestration**: uses [coder-utils](https://registry.coder.com/modules/coder/coder-utils) for `coder exp sync` based script ordering so downstream modules can serialize their own scripts behind this module

## Examples

### Task log snapshot

Enabled by default. Captures the last 10 messages from AgentAPI when a task workspace stops.

```tf
module "agentapi" {
  # ... other config
  task_log_snapshot = true # default
}
```

### State persistence

Disabled by default. Requires agentapi >= v0.12.0.

```tf
module "agentapi" {
  # ... other config
  enable_state_persistence = true
}
```

Custom file paths:

```tf
module "agentapi" {
  # ... other config
  enable_state_persistence = true
  state_file_path          = "/custom/path/state.json"
  pid_file_path            = "/custom/path/agentapi.pid"
}
```

### Script serialization

The module outputs `scripts`, an ordered list of `coder exp sync` names. Downstream modules can use these to serialize their own `coder_script` resources behind the install pipeline:

```tf
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  # ...
}

output "scripts" {
  value = module.agentapi.scripts
}
```

## For module developers

For a complete example of how to build a module on top of AgentAPI, see the [Goose module](https://github.com/coder/registry/blob/main/registry/coder/modules/goose/main.tf).

## Troubleshooting

- Install logs are written to `~/.coder-modules/coder/agentapi/logs/install.log`
- AgentAPI server logs are written to `~/.coder-modules/coder/agentapi/agentapi-start.log`
- Check `agentapi --version` to verify the installed binary version
