---
display_name: VS Code Desktop
description: Add a one-click button to launch VS Code Desktop
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode]
---

# VS Code Desktop

Add a button to open any workspace with a single click.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

### Pre-install extensions

Pre-install VS Code extensions so they are ready when the user first connects:

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  extensions = [
    "ms-python.python",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
  ]
}
```

### Pre-install extensions with custom settings

Apply machine-level settings on the remote host. Settings are merged with any existing machine settings:

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  extensions = [
    "ms-python.python",
    "esbenp.prettier-vscode",
  ]
  settings = {
    "editor.fontSize"    = 14
    "editor.tabSize"     = 2
    "editor.formatOnSave" = true
    "python.defaultInterpreterPath" = "/usr/bin/python3"
  }
}
```
