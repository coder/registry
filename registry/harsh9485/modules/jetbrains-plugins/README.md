---
display_name: JetBrains Plugin Installer
description: Companion module for coder/jetbrains that automatically installs JetBrains Marketplace plugins.
icon: ../../../../.icons/jetbrains.svg
tags: [ide, jetbrains, plugins]
---

# JetBrains Plugin Installer

A companion module for
[coder/jetbrains](https://registry.coder.com/modules/jetbrains) that
automatically installs JetBrains Marketplace plugins into your workspace.

Use this alongside the core `coder/jetbrains` module — it handles plugin
installation while `coder/jetbrains` handles IDE setup and Toolbox
integration.

```tf
module "jetbrains_plugins" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/harsh9485/jetbrains-plugins/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id

  jetbrains_plugins = {
    "PY" = ["com.koxudaxi.pydantic", "com.intellij.kubernetes"]
  }
}
```

## Prerequisites

- The [coder/jetbrains](https://registry.coder.com/modules/jetbrains)
  module (or equivalent JetBrains Toolbox setup) must already be
  configured in your template.
- `jq` must be available on `PATH`.
- Linux environment only.

## Finding Plugin IDs

Open the plugin page on the
[JetBrains Marketplace](https://plugins.jetbrains.com/). Scroll to
**Additional Information** and copy the **Plugin ID**.

## Usage

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.4.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["PY", "GO"]
}

module "jetbrains_plugins" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/harsh9485/jetbrains-plugins/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id

  jetbrains_plugins = {
    "PY" = ["com.koxudaxi.pydantic", "com.intellij.kubernetes"]
    "GO" = ["org.jetbrains.plugins.go-template"]
  }
}
```

The keys in `jetbrains_plugins` are IDE product codes (`PY`, `GO`, `IU`,
etc.) matching the codes used by the `coder/jetbrains` module. Each value
is a list of Marketplace plugin IDs to install for that IDE.

> [!IMPORTANT]
> After installing the IDE, restart the workspace. On the next start the
> module detects installed IDEs and automatically installs the configured
> plugins.

Some plugins may be disabled by default due to JetBrains security
defaults — you might need to enable them manually in the IDE.
