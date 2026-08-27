---
display_name: MCP Servers
description: Select and configure popular official MCP servers for multiple workspace agents.
icon: ../../../../.icons/mcp.svg
verified: false
tags: [mcp, ai, agent, helper]
---

# MCP Servers

Adds a multi-select field to the workspace creation form and configures each selected MCP server for every requested agent client. The module uses [mcp-add](https://github.com/paoloricciuti/mcp-add) to preserve each client's native configuration format.

The multi-select workspace parameter requires Coder 2.24 or newer.

```tf
module "mcp_servers" {
  source  = "registry.coder.com/coder/mcp-servers/coder"
  version = "1.0.0"

  agent_id = coder_agent.main.id
  clients  = ["claude code", "codex"]
}
```

The initial catalog includes the official [GitHub MCP Server](https://github.com/github/github-mcp-server) and [Playwright MCP](https://github.com/microsoft/playwright-mcp).

## GitHub authentication

The module configures the GitHub MCP endpoint but does not store credentials. VS Code can authenticate with GitHub OAuth. Claude Code and other clients without GitHub OAuth support require a GitHub Personal Access Token in the `Authorization` header. Follow the [official client-specific authentication guide](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/README.md) for the selected client.

For example, if Claude Code reports that dynamic client registration is unsupported, the server configuration is valid but its OAuth method is not compatible. Configure the GitHub MCP server with a PAT instead of retrying OAuth.

The selection is immutable for the lifetime of a workspace because removing a server from the field cannot safely remove configuration that the user may have customized. Rebuild the workspace to change the selection.

When a non-empty Codex configuration already exists, the module validates it with the installed Codex CLI before making changes. Ensure the Codex module runs first; malformed TOML is left unchanged with an actionable error.

## Preselect servers

Template authors can preselect one or both servers while still allowing users to change the choice when creating a workspace.

```tf
module "mcp_servers" {
  source  = "registry.coder.com/coder/mcp-servers/coder"
  version = "1.0.0"

  agent_id = coder_agent.main.id
  clients  = ["gemini", "windsurf"]
  default  = ["github", "playwright"]
}
```

The module reuses Node.js 18 or newer when available. Otherwise it downloads a pinned Node.js runtime into `$HOME/.coder-modules/coder/mcp-servers/dependencies`, verifies the official SHA-256 checksum, and keeps the runtime isolated to this module.
