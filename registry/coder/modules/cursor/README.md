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
  version  = "1.3.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Configure MCP servers for Cursor

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.cursor/mcp.json` using a `coder_script` on workspace start.

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
  mcp = jsonencode({
    mcpServers = {
      coder = {
        command = "coder"
        args    = ["exp", "mcp", "server"]
        env = {
          CODER_MCP_APP_STATUS_SLUG = "cursor"
          CODER_MCP_AI_AGENTAPI_URL = "http://localhost:3284"
        }
      }
    }
  })
}
```
