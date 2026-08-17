---
display_name: Devin Desktop
description: Add a one-click button to launch Devin Desktop (formerly Windsurf Editor)
icon: ../../../../.icons/devin.svg
verified: true
tags: [ide, devin, windsurf, ai]
---

# Devin Desktop

> [!NOTE]
> Devin Desktop is Cognition's June 2, 2026 rebrand of the Windsurf Editor (itself a rebrand of Codeium's
> original editor). It reuses Windsurf's `~/.codeium/windsurf/` MCP config path.

> [!IMPORTANT]
> This module defaults to opening Devin Desktop via a `devin://` deep link, a placeholder that has not
> been independently verified against a live Devin Desktop install. Opening `devin://` links also requires
> `"devin:"` to be registered in Coder's `ALLOWED_EXTERNAL_APP_PROTOCOLS`
> ([coder/coder#28214](https://github.com/coder/coder/pull/28214)), so this module should not be tagged/released
> until that ships in a released Coder version. Override the `protocol` input (e.g. back to `"windsurf"`) if
> needed in the meantime.

Add a button to open any workspace with a single click in Devin Desktop.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

### Configure MCP servers for Devin Desktop

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.codeium/windsurf/mcp_config.json` using a `coder_script` on workspace start.

The following example configures Devin Desktop to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
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
