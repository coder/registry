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

### Configure MCP servers for Trae CN

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `.trae/mcp.json` in `folder`, or `$HOME/.trae/mcp.json` when `folder` is not set.

If your MCP configuration includes credentials, either add `.trae/mcp.json` to the project's `.gitignore`, or set `mcp_config_path` to a path outside the repository.

The following example configures Trae CN to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "trae_cn" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/trae-cn/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
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
