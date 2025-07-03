---
display_name: Zed IDE
description: Add a one-click button to launch Zed IDE
icon: ../../../../.icons/zed.svg
maintainer_github: coder
verified: true
tags: [ide, zed, editor]
---

# Zed IDE

Add a button to open any workspace with a single click in Zed IDE.

Zed is a high-performance, multiplayer code editor from the creators of Atom and Tree-sitter.

```tf
module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Custom display name and order

```tf
module "zed" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/zed/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  display_name = "Zed Editor"
  order        = 1
}
```
