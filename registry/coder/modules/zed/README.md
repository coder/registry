---
display_name: Zed
description: Add a one-click button to launch Zed
icon: ../../../../.icons/zed.svg
verified: true
tags: [ide, zed, editor]
---

# Zed

Add a button to open any workspace with a single click in Zed.

Zed is a high-performance, multiplayer code editor from the creators of Atom and Tree-sitter.

> [!IMPORTANT]
> Zed needs you to either have Coder CLI installed with `coder config-ssh` run or [Coder Desktop](https://coder.com/docs/user-guides/desktop)

```tf
module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Custom display name and order

```tf
module "zed" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/zed/coder"
  version      = "1.1.0"
  agent_id     = coder_agent.example.id
  display_name = "Zed Editor"
  order        = 1
}
```

### With custom agent name

```tf
module "zed" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/zed/coder"
  version    = "1.1.0"
  agent_id   = coder_agent.example.id
  agent_name = coder_agent.example.name
}
```

### Configure Zed settings including MCP servers

Zed stores settings at `~/.config/zed/settings.json` by default. If `XDG_CONFIG_HOME` is set on Linux, settings will be at `$XDG_CONFIG_HOME/zed/settings.json`.

You can declaratively set/merge settings with the `settings` input. Provide a JSON string (e.g., via `jsonencode(...)`). For example, to configure MCP servers:

```tf
module "zed" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id

  settings = jsonencode({
    context_servers = {
      your-mcp-server = {
        source  = "custom"
        command = "some-command"
        args    = ["arg-1", "arg-2"]
        env     = {}
      }
    }
  })
}
```

See Zed’s settings files documentation: https://zed.dev/docs/configuring-zed#settings-files
