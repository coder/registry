---
display_name: VS Code Desktop
description: Add a one-click button to launch VS Code Desktop with pre-installed extensions and settings.
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode]
---

# VS Code Desktop

Add a button to open any workspace with a single click. This module can also pre-install VS Code extensions and apply custom settings for a ready-to-code environment.

It uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

## Basic Usage

```tf
module "vscode" {
  source   = "[registry.coder.com/coder/vscode-desktop/coder](https://registry.coder.com/coder/vscode-desktop/coder)"
  version  = "1.2.0" # Or latest version
  agent_id = coder_agent.example.id
}
```
## Examples

### Open in a specific directory

```tf
module "vscode" {
  source   = "[registry.coder.com/coder/vscode-desktop/coder](https://registry.coder.com/coder/vscode-desktop/coder)"
  version  = "1.2.0" # Or latest version
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

## Pre-install extensions and apply settings

```tf
module "vscode" {
  source   = "[registry.coder.com/coder/vscode-desktop/coder](https://registry.coder.com/coder/vscode-desktop/coder)"
  version  = "1.2.0" # Or latest version
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  # A list of extension IDs from the VS Code Marketplace to install on startup.
  extensions = [
    "ms-python.python",
    "golang.go",
    "hashicorp.terraform",
    "esbenp.prettier-vscode"
  ]

  # A map of settings that will be converted to JSON
  # and written to the settings file. Use the jsonencode function for this.
  settings = jsonencode({
    "editor.fontSize": 14,
    "terminal.integrated.fontSize": 12,
    "workbench.colorTheme": "Default Dark+",
    "editor.formatOnSave": true
  })
}
```
