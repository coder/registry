---
display_name: Cursor IDE
description: Add a one-click button to launch Cursor IDE
icon: ../../../../.icons/cursor.svg
verified: true
tags: [ide, cursor, ai]
---

# Cursor IDE

Add a button to open any workspace with a single click in Cursor IDE.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.2.1"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.2.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```
