---
display_name: Shux
description: Coding Agent Multiplexer - Run multiple AI agents in parallel
icon: ../../../../.icons/shux.svg
verified: true
tags: [ai, agents, development, multiplexer]
---

# Shux

Automatically install and run [Shux](https://github.com/coder/shux) (formerly Mux) in a Coder workspace. By default, the module auto-detects an available package manager (`npm`, `pnpm`, or `bun`) to install `@coder/shux@next` (with a fallback to downloading the npm tarball if none is found). You can also force a specific package manager via `package_manager` and point to a custom registry with `registry_url`. The launcher keeps watching the shux process after startup, appends signal/exit-code diagnostics to the shux log when the server is killed outside the Node runtime, and can optionally wait a few seconds, remove the stale server lock, and restart Shux after any exit until an optional restart-attempt cap is reached. Shux is a desktop application for parallel agentic development that enables developers to run multiple AI agents simultaneously across isolated workspaces.

```tf
module "shux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/shux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

![Shux](../../.images/shux-product-hero.webp)

## Features

- **Parallel Agent Execution**: Run multiple AI agents simultaneously on different tasks
- **Shux Workspace Isolation**: Each agent works in its own isolated environment
- **Git Divergence Visualization**: Track changes across different Shux agent workspaces
- **Long-Running Processes**: Resume AI work after interruptions
- **Cost Tracking**: Monitor API usage across agents

## Migrating from the `mux` module

This module replaces the deprecated [`mux`](https://registry.coder.com/modules/coder/mux) module after the product rename. Besides the name, note these differences:

- Installs the `@coder/shux` npm package instead of `mux`.
- Runtime data moved from `/tmp` to `$HOME/.coder-modules/coder/shux/`: the install prefix defaults to `$HOME/.coder-modules/coder/shux/install` and the server log to `$HOME/.coder-modules/coder/shux/logs/shux.log`, so both now survive workspace restarts.
- Install and start are orchestrated through the [`coder-utils`](https://registry.coder.com/modules/coder/coder-utils) module, which writes script output to `$HOME/.coder-modules/coder/shux/logs/` and exposes a `scripts` output plus optional `pre_install_script`/`post_install_script` hooks.
- The workspace app slug defaults to `shux`, so pinned app URLs change.

## Examples

### Basic Usage

```tf
module "shux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/shux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### Pin Version

```tf
module "shux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/shux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  # Default is the "next" dist-tag; set to a specific version to pin
  install_version = "0.28.2"
}
```

### Open a Project on Launch

Start Shux with `shux server --add-project /path/to/project`:

```tf
module "shux" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/shux/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.main.id
  add_project = "/path/to/project"
}
```

### Pass Arbitrary `shux server` Arguments

Use `additional_arguments` to append additional arguments to `shux server`.
The module parses quoted values, so grouped arguments remain intact.

```tf
module "shux" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/shux/coder"
  version              = "1.0.0"
  agent_id             = coder_agent.main.id
  additional_arguments = "--open-mode pinned --add-project '/workspaces/my repo'"
}
```

### Restart After Shux Exits

Enable automatic restarts after Shux exits, including clean exits and intentional shutdown signals such as `SIGTERM`. The launcher waits for `restart_delay_seconds`, removes the stale server lock (`~/.shux/server.lock`, plus the legacy `~/.mux/server.lock`), and starts Shux again. Set `max_restart_attempts` to a whole number to stop retrying after a fixed number of restarts, or leave it at `0` for unlimited retries.

```tf
module "shux" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/coder/shux/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  restart_on_kill       = true
  restart_delay_seconds = 3
  max_restart_attempts  = 5
}
```

### Custom Port

```tf
module "shux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/shux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  port     = 8080
}
```

### Custom Package Manager

Force a specific package manager instead of auto-detection:

```tf
module "shux" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/shux/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  package_manager = "pnpm" # or "npm", "bun"
}
```

### Custom Registry

Use a private or mirrored npm registry:

```tf
module "shux" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/shux/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  registry_url = "https://npm.pkg.github.com"
}
```

### Use Cached Installation

Run an existing copy of Shux if found, otherwise install from npm:

```tf
module "shux" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/shux/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  use_cached = true
}
```

### Skip Install

Run without installing from the network (requires Shux to be pre-installed):

```tf
module "shux" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/shux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  install  = false
}
```

## Supported Platforms

- Linux (x86_64, aarch64)

## Notes

- Requires internet connectivity for agent operations (unless `install` is set to false)
- Auto-detects `npm`, `pnpm`, or `bun` by default; set `package_manager` to force a specific one
- Requires a Node.js runtime; if `node` is not on the workspace `PATH`, the module bootstraps a pinned Node.js runtime into `$HOME/.coder-modules/coder/shux/node` (override the version with the `SHUX_NODE_VERSION` environment variable)
- Installs `@coder/shux@next` from the npm registry by default; set `registry_url` to use a private or mirrored registry
- Falls back to a direct tarball download when no package manager is found
- Module data (install, logs, scripts) lives under `$HOME/.coder-modules/coder/shux/`; install and start script output is written to the `logs/` subdirectory
- Appends best-effort signal and external-kill diagnostics to `log_path` if the shux process dies after startup
- Set `restart_on_kill = true` to wait `restart_delay_seconds`, remove the stale server locks, and restart Shux after it exits
- Set `max_restart_attempts` to a whole-number cap on restart attempts, or leave it at `0` for unlimited retries
