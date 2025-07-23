---
display_name: Kiro IDE
description: Add a one-click button to launch Kiro IDE
icon: ../../../../.icons/kiro.svg
verified: true
tags: [ide, kiro, ai, aws]
---

# Kiro IDE

Add a button to open any workspace with a single click in [Kiro IDE](https://kiro.dev).

Kiro is an AI-powered IDE from AWS that helps developers build from concept to production with spec-driven development, featuring AI agents, hooks, and steering files.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder) and [open-remote-ssh extension](https://open-vsx.org/extension/jeanp413/open-remote-ssh) for establishing connections to Coder workspaces.

```tf
module "kiro" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/kiro/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "kiro" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/kiro/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Open with custom display name and order

```tf
module "kiro" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/kiro/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  display_name = "Kiro AI IDE"
  order        = 1
}
```
