---
display_name: JetBrains Fleet
description: Add a one-click button to launch JetBrains Fleet to connect to your workspace.
icon: ../../../../.icons/fleet.svg
verified: true
tags: [ide, jetbrains, fleet]
---

# Jetbrains Fleet

> [!WARNING]
> **Deprecation Notice:** JetBrains has announced that Fleet will be discontinued. For more information, see [The Future of Fleet](https://blog.jetbrains.com/fleet/2025/12/the-future-of-fleet). Consider migrating to other JetBrains IDEs such as IntelliJ IDEA, PyCharm, or GoLand with the [JetBrains Gateway](https://registry.coder.com/modules/jetbrains-gateway) module.

This module adds a Jetbrains Fleet button to your Coder workspace that opens the workspace in JetBrains Fleet using SSH remote development.

JetBrains Fleet is a next-generation IDE that supports collaborative development and distributed architectures. It connects to your Coder workspace via SSH, providing a seamless remote development experience.

```tf
module "jetbrains_fleet" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains-fleet/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
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
  version  = "1.0.3"
  agent_id = coder_agent.main.id
}
```

### Open a specific folder

```tf
module "jetbrains_fleet" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains-fleet/coder"
  version  = "1.0.3"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

### Customize app name and grouping

```tf
module "jetbrains_fleet" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/jetbrains-fleet/coder"
  version      = "1.0.3"
  agent_id     = coder_agent.main.id
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
  version    = "1.0.3"
  agent_id   = coder_agent.main.id
  agent_name = coder_agent.example.name
}
```
