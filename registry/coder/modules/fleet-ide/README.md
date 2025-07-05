---
display_name: JetBrains Fleet
description: Add a one-click button to launch JetBrains Fleet IDE to connect to your workspace.
icon: ../../../../.icons/jetbrains.svg
maintainer_github: coder
verified: false
tags: [ide, jetbrains, fleet]
---

# Fleet IDE

This module adds a Fleet IDE button to your Coder workspace that opens the workspace in JetBrains Fleet using SSH remote development.

JetBrains Fleet is a next-generation IDE that supports collaborative development and distributed architectures. It connects to your Coder workspace via SSH, providing a seamless remote development experience.

```tf
module "fleet_ide" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/fleet-ide/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

![Fleet IDE](../.images/fleet-ide.png)

## Requirements

- JetBrains Fleet must be installed locally on your development machine
- Download Fleet from: https://www.jetbrains.com/fleet/

> [IMPORTANT]
> Fleet needs you to either have Coder CLI installed with `coder config-ssh` run or [Coder Desktop](https://coder.com/docs/user-guides/desktop).

## Examples

### Basic usage

```tf
module "fleet_ide" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/fleet-ide/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Open a specific folder

```tf
module "fleet_ide" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/fleet-ide/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Customize app name and grouping

```tf
module "fleet_ide" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/fleet-ide/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  display_name = "Fleet"
  group        = "JetBrains IDEs"
  order        = 1
}
```
