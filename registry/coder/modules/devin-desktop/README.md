---
display_name: Devin Desktop
description: Add a one-click button to launch Devin Desktop (formerly Windsurf Editor)
icon: ../../../../.icons/devin.svg
verified: true
tags: [ide, devin, ai]
---

# Devin Desktop

Add a button to open any workspace with a single click in Devin Desktop.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

### Pre-install extensions on the workspace host

Use `extensions` to install Devin-compatible VS Code extension IDs before the first ordinary Devin Desktop connection. The module downloads the official Devin Remote Host from the editor's stable update service, verifies the published SHA-256 checksum, and installs extensions under `~/.devin-server/extensions`.

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"

  extensions = [
    "ms-python.python",
    "esbenp.prettier-vscode@12.4.0",
  ]
}
```

The installation blocks ordinary workspace login for up to 30 minutes so extensions are ready before Devin Desktop connects. A download, checksum, extraction, or extension installation failure remains visible in the Coder startup logs. Later workspace starts reuse an existing executable Remote Host and do not force extension updates.

The workspace image must provide Bash, `base64`, `tar`, either `curl` or `wget`, and either `sha256sum` or `shasum`. The workspace also needs HTTPS egress to the editor update and artifact hosts. Extension availability and compatibility depend on the configured extension marketplace; use `publisher.extension@version` to request a specific version.

### Configure MCP servers for Devin Desktop

Provide a JSON-encoded string via the `mcp` input. When set, the module writes the value to `~/.config/devin/mcp_config.json` using a `coder_script` on workspace start.

The following example configures Devin Desktop to use the GitHub MCP server with authentication facilitated by the [`coder_external_auth`](https://coder.com/docs/admin/external-auth#configure-a-github-oauth-app) resource.

```tf
module "devin-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devin-desktop/coder"
  version  = "1.1.0"
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
