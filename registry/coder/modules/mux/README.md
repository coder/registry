---
display_name: Mux
description: Coding Agent Multiplexer - Run multiple AI agents in parallel
icon: ../../../../.icons/mux.svg
verified: true
tags: [ai, agents, development, multiplexer]
---

# Mux

Automatically install and run [Mux](https://github.com/coder/mux) in a Coder workspace. By default, the module auto-detects an available package manager (`npm`, `pnpm`, or `bun`) to install `mux@next` (with a fallback to downloading the npm tarball if none is found). You can also force a specific package manager via `package_manager` and point to a custom registry with `registry_url`. Mux is a desktop application for parallel agentic development that enables developers to run multiple AI agents simultaneously across isolated workspaces.

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
}
```

![Mux](../../.images/mux-product-hero.webp)

## Features

- **Parallel Agent Execution**: Run multiple AI agents simultaneously on different tasks
- **Mux Workspace Isolation**: Each agent works in its own isolated environment
- **Git Divergence Visualization**: Track changes across different Mux agent workspaces
- **Long-Running Processes**: Resume AI work after interruptions
- **Cost Tracking**: Monitor API usage across agents

## Examples

### Basic Usage

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
}
```

### Pin Version

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
  # Default is "latest"; set to a specific version to pin
  install_version = "0.4.0"
}
```

### Open a Project on Launch

Start Mux with `mux server --add-project /path/to/project`:

```tf
module "mux" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/mux/coder"
  version     = "1.3.1"
  agent_id    = coder_agent.main.id
  add_project = "/path/to/project"
}
```

### Pass Arbitrary `mux server` Arguments

Use `additional_arguments` to append additional arguments to `mux server`.
The module parses quoted values, so grouped arguments remain intact.

```tf
module "mux" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/mux/coder"
  version              = "1.3.1"
  agent_id             = coder_agent.main.id
  additional_arguments = "--open-mode pinned --add-project '/workspaces/my repo'"
}
```

### Custom Port

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
  port     = 8080
}
```

### Custom Package Manager

Force a specific package manager instead of auto-detection:

```tf
module "mux" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/mux/coder"
  version         = "1.3.1"
  agent_id        = coder_agent.main.id
  package_manager = "pnpm" # or "npm", "bun"
}
```

### Custom Registry

Use a private or mirrored npm registry:

```tf
module "mux" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/mux/coder"
  version      = "1.3.1"
  agent_id     = coder_agent.main.id
  registry_url = "https://npm.pkg.github.com"
}
```

### Use Cached Installation

Run an existing copy of Mux if found, otherwise install from npm:

```tf
module "mux" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/mux/coder"
  version    = "1.3.1"
  agent_id   = coder_agent.main.id
  use_cached = true
}
```

### Skip Install

Run without installing from the network (requires Mux to be pre-installed):

```tf
module "mux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/mux/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
  install  = false
}
```

## Supported Platforms

- Linux (x86_64, aarch64)

## Notes

- Mux is currently in preview and you may encounter bugs
- Requires internet connectivity for agent operations (unless `install` is set to false)
- Auto-detects `npm`, `pnpm`, or `bun` by default; set `package_manager` to force a specific one
- Installs `mux@next` from the npm registry by default; set `registry_url` to use a private or mirrored registry
- Falls back to a direct tarball download when no package manager is found
