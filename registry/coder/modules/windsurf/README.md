---
display_name: Windsurf Editor
description: Add a one-click button to launch Windsurf Editor
icon: ../../../../.icons/windsurf.svg
verified: true
tags: [ide, windsurf, ai]
---

# Windsurf Editor

Add a button to open any workspace with a single click in Windsurf Editor.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "windsurf" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windsurf/coder"
  version  = "1.2.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "windsurf" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windsurf/coder"
  version  = "1.2.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Configure MCP servers for Windsurf

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.codeium/windsurf/mcp_config.json` using a `coder_script` on workspace start.

The following example configures Windsurf to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "windsurf" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windsurf/coder"
  version  = "1.2.0"
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
