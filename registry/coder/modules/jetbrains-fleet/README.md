---
display_name: JetBrains Fleet
description: Add a one-click button to launch JetBrains Fleet to connect to your workspace.
icon: ../../../../.icons/jetbrains.svg
verified: true
tags: [ide, jetbrains, fleet]
---

# Jetbrains Fleet

This module adds a Jetbrains Fleet button to your Coder workspace that opens the workspace in JetBrains Fleet using SSH remote development.

JetBrains Fleet is a next-generation IDE that supports collaborative development and distributed architectures. It connects to your Coder workspace via SSH, providing a seamless remote development experience.

```tf
module "jetbrains_fleet" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains-fleet/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Requirements

- JetBrains Fleet must be installed locally on your development machine
- Download Fleet from: https://www.jetbrains.com/fleet/

> [!IMPORTANT]
> Fleet needs you to either have Coder CLI installed with `coder config-ssh` run or [Coder Desktop](https://coder.com/docs/user-guides/desktop).

## Examples

### Basic usage

```tf
module "jetbrains_fleet" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains-fleet/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Open a specific folder

```tf
module "jetbrains_fleet" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains-fleet/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Customize app name and grouping

```tf
module "jetbrains_fleet" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/jetbrains-fleet/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  display_name = "Fleet"
  group        = "JetBrains IDEs"
  order        = 1
}
```

### With custom agent name

```tf
module "jetbrains_fleet" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains-fleet/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  agent_name = coder_agent.example.name
}
```
