---
display_name: Positron Desktop
description: Add a one-click button to launch Positron Desktop
icon: ../../../../.icons/positron.svg
verified: true
tags: [ide, positron]
---

# Positron Desktop

Add a button to open any workspace with a single click.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "positron" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/cytoshahar/positron/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "positron" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/cytoshahar/positron/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

Based on the [Coder VS Code Desktop Module](https://github.com/coder/registry/tree/main/registry/coder/modules/vscode-desktop)
