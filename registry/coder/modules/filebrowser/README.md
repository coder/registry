---
display_name: File Browser
description: A file browser for your workspace
icon: ../../../../.icons/filebrowser.svg
maintainer_github: coder
verified: true
tags: [filebrowser, web]
---

# File Browser

A file browser for your workspace.

```tf
module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/filebrowser/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}
```

![Filebrowsing Example](../../.images/filebrowser.png)

## Examples

### Serve a specific directory

```tf
module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/filebrowser/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Specify location of `filebrowser.db`

```tf
module "filebrowser" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/coder/filebrowser/coder"
  version       = "1.0.31"
  agent_id      = coder_agent.example.id
  database_path = ".config/filebrowser.db"
}
```

### Serve from the same domain (no subdomain)

```tf
module "filebrowser" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/filebrowser/coder"
  version    = "1.0.31"
  agent_id   = coder_agent.example.id
  agent_name = "main"
  subdomain  = false
}
```
