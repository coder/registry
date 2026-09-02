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
  source  = "registry.coder.com/coder-labs/mcp-servers/coder"
  version = "0.0.1"

  agent_id = coder_agent.main.id
  clients  = ["claude code", "codex"]
}
```

The initial catalog includes the official [GitHub MCP Server](https://github.com/github/github-mcp-server) and [Playwright MCP](https://github.com/microsoft/playwright-mcp).

## GitHub authentication

By default, the module configures the GitHub MCP endpoint without credentials. This preserves the original behavior and lets clients with compatible OAuth support authenticate themselves.

For Claude Code, Codex, and Cursor, `token-env` references a workspace environment variable without writing its value to any MCP configuration file:

```tf
module "mcp_servers" {
  source  = "registry.coder.com/coder-labs/mcp-servers/coder"
  version = "0.0.1"

  agent_id = coder_agent.main.id
  clients  = ["claude code", "codex", "cursor"]
  default  = ["github"]

  github_auth = {
    mode          = "token-env"
    token_env_var = "GITHUB_MCP_TOKEN"
  }
}
```

Template authors can inject a shared value through the agent environment. Everyone with shell access to the workspace can read it, and rotation requires updating the template-provided value and restarting the workspace.

For per-user values, create an enabled [Coder User Secret](https://coder.com/docs/user-guides/user-secrets) targeting the same variable. Provide the value over standard input so it does not appear in shell history or process arguments:

```sh
echo -n "$GITHUB_TOKEN" | coder secret create github-mcp --env GITHUB_MCP_TOKEN
```

Coder applies a new, modified, disabled, or re-enabled secret on the next workspace start. If the required variable is absent, the module fails with an actionable message instead of reporting authenticated success.

### Coder External Auth

Claude Code can resolve a short-lived token at connection time with `coder external-auth access-token`. The module creates a `headersHelper` under `$HOME/.coder-modules/coder-labs/mcp-servers/scripts/`; it never stores the returned token.

```tf
github_auth = {
  mode             = "external-auth"
  external_auth_id = "primary-github"
}
```

This mode intentionally accepts Claude Code only. Codex's HTTP helper cannot set the reserved `Authorization` header, and Cursor has no documented dynamic-header helper, so those combinations fail during Terraform planning. Use `token-env` with a User Secret for Codex or Cursor.

### Native GitHub OAuth

`native-oauth` replaces the remote GitHub entry with the official local stdio server for every selected client. The default image is versioned and pinned by digest. The callback port is published on loopback only, and the server can fall back to GitHub's device flow in a headless workspace.

```tf
github_auth = {
  mode                = "native-oauth"
  oauth_callback_port = 8085
}
```

This opt-in mode requires Docker inside the workspace. The official server keeps its OAuth token in memory; the module does not create a token file. A PAT still takes precedence if the local server receives `GITHUB_PERSONAL_ACCESS_TOKEN` from the workspace environment.

The hosted GitHub MCP endpoint currently documents PAT authentication for Claude Code and Cursor. If Claude Code reports that dynamic client registration is unsupported, use `token-env`, Coder External Auth, or the local native OAuth mode instead of retrying the incompatible flow. Follow the [official client-specific authentication guide](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/README.md) for client details.

The selection is immutable for the lifetime of a workspace because removing a server from the field cannot safely remove configuration that the user may have customized. Rebuild the workspace to change the selection.

When a non-empty Codex configuration already exists, the module validates it with the installed Codex CLI before making changes. Ensure the Codex module runs first; malformed TOML is left unchanged with an actionable error.

For a prebuilt workspace, the initial `prebuilds` owner receives only the unauthenticated MCP structure. User Secret injection, External Auth resolution, and OAuth startup are skipped. Coder reruns Terraform with the final owner during claim, and the authentication post-install script is then recalculated for that owner.

## Preselect servers

Template authors can preselect one or both servers while still allowing users to change the choice when creating a workspace.

```tf
module "mcp_servers" {
  source  = "registry.coder.com/coder-labs/mcp-servers/coder"
  version = "0.0.1"

  agent_id = coder_agent.main.id
  clients  = ["gemini", "windsurf"]
  default  = ["github", "playwright"]
}
```

The module reuses Node.js 18 or newer when available. Otherwise it downloads a pinned Node.js runtime into `$HOME/.coder-modules/coder-labs/mcp-servers/dependencies`, verifies the official SHA-256 checksum, and keeps the runtime isolated to this module.
