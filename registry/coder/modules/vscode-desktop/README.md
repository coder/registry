---
display_name: VS Code Desktop
description: Add a one-click button to launch VS Code Desktop with pre-installed extensions and settings
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode]
---

# VS Code Desktop

Add a button to open any workspace with a single click, with support for pre-installing extensions and configuring settings.

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.1"
  agent_id = coder_agent.example.id
}
```

## Examples

### With extensions and settings

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  extensions = [
    "ms-python.python",
    "golang.go"
  ]
  settings = {
    "editor.fontSize" = 14
    "files.autoSave"  = "afterDelay"
  }
}
```
