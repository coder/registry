---
display_name: VS Code Desktop
description: Add a one-click button to launch VS Code Desktop
icon: ../../../../.icons/code.svg
maintainer_github: coder
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
  version  = "1.1.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Auto-install extensions and configure settings

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  
  # Auto-install Python development extensions
  extensions = [
    "ms-python.python",
    "ms-python.pylint",
    "ms-toolsai.jupyter"
  ]
  
  # Configure workspace settings
  settings = {
    "editor.fontSize" = 14
    "editor.tabSize" = 2
    "python.defaultInterpreterPath" = "/usr/bin/python3"
    "workbench.colorTheme" = "Dark+ (default dark)"
  }
}
```

### Disable automatic extension installation

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  extensions = ["ms-python.python"]
  install_extensions = false  # Only create recommendations, don't install
}
```
