---
display_name: cmux
description: Coding Agent Multiplexer - Run multiple AI agents in parallel
icon: ../../../../.icons/cmux.svg
verified: false
tags: [ai, agents, development, multiplexer]
---

# cmux

Automatically install and run [cmux](https://github.com/coder/cmux) in a workspace. By default, the module installs `@coder/cmux@latest` from npm (with a fallback to downloading the npm tarball if npm is unavailable). cmux is a desktop application for parallel agentic development that enables developers to run multiple AI agents simultaneously across isolated workspaces.

```tf
module "cmux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- **Parallel Agent Execution**: Run multiple AI agents simultaneously on different tasks
- **Workspace Isolation**: Each agent works in its own isolated environment
- **Git Divergence Visualization**: Track changes across different agent workspaces
- **Long-Running Processes**: Resume AI work after interruptions
- **Cost Tracking**: Monitor API usage across agents

## Examples

### Basic Usage

```tf
module "cmux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Pin Version

```tf
module "cmux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  # Default is "latest"; set to a specific version to pin
  install_version = "0.4.0"
}
```

### Custom Port

```tf
module "cmux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  port     = 8080
}
```

### Use Cached Installation

Run an existing copy of cmux if found, otherwise install from npm:

```tf
module "cmux" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/cmux/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  use_cached = true
}
```

### Offline Mode

Just run cmux in the background; do not install from the network (requires cmux to be pre-installed):

```tf
module "cmux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  offline  = true
}
```

## Supported Platforms

- Linux (x86_64, aarch64)

## Notes

- cmux is currently in preview and you may encounter bugs
- Requires internet connectivity for agent operations (unless running in offline mode)
- Installs `@coder/cmux` from npm by default (falls back to the npm tarball if npm is unavailable)
