---
display_name: Trae CN
description: Add a one-click button to launch Trae CN
icon: ../../../../.icons/trae-cn.png
verified: false
tags: [ide, trae, ai]
---

# Trae CN

Add a button to open any workspace with a single click in Trae CN.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "trae_cn" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/trae-cn/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "trae_cn" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/trae-cn/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```
