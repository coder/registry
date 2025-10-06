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
  version  = "1.1.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Open in a specific directory

```tf
module "kiro" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/kiro/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

### Configure MCP servers for Kiro

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.kiro/settings/mcp.json` using a `coder_script` on workspace start.

The following example configures Kiro to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "kiro" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/kiro/coder"
  version  = "1.1.0"
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
