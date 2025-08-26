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
  version  = "1.3.1"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Configure MCP servers for Cursor

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.cursor/mcp.json` using a `coder_script` on workspace start.

The following example configures Cursor to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  mcp = jsonencode({
    mcpServers = {
      "github" : {
        "url" : "https://api.githubcopilot.com/mcp/",
        "headers" : {
          "Authorization" : "Bearer ${data.coder_external_auth.github.access_token}",
        },
        "type" : "http"
      }
    }
  })
}

data "coder_external_auth" "github" {
  id = "github"
}
```
