---
display_name: mux
description: Coding Agent Multiplexer - Run multiple AI agents in parallel
icon: ../../../../.icons/mux.svg
verified: true
tags: [ai, agents, development, multiplexer]
---

# mux

Automatically install and run [mux](https://github.com/coder/mux) in a Coder workspace. By default, the module installs `mux@next` from npm (with a fallback to downloading the npm tarball if npm is unavailable). mux is a desktop application for parallel agentic development that enables developers to run multiple AI agents simultaneously across isolated workspaces.

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
}
```

## Features

- **Parallel Agent Execution**: Run multiple AI agents simultaneously on different tasks
- **Mux Workspace Isolation**: Each agent works in its own isolated environment
- **Git Divergence Visualization**: Track changes across different mux agent workspaces
- **Long-Running Processes**: Resume AI work after interruptions
- **Cost Tracking**: Monitor API usage across agents

## Examples

### Basic Usage

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
}
```

### Pin Version

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
  # Default is "latest"; set to a specific version to pin
  install_version = "0.4.0"
}
```

### Custom Port

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
  port     = 8080
}
```

### Use Cached Installation

Run an existing copy of mux if found, otherwise install from npm:

```tf
module "mux" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/mux/coder"
  version    = "1.0.3"
  agent_id   = coder_agent.main.id
  use_cached = true
}
```

### Skip Install

Run without installing from the network (requires mux to be pre-installed):

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
  install  = false
}
```

## Supported Platforms

- Linux (x86_64, aarch64)

## Notes

- mux is currently in preview and you may encounter bugs
- Requires internet connectivity for agent operations (unless `install` is set to false)
- Installs `mux@next` from npm by default (falls back to the npm tarball if npm is unavailable)
