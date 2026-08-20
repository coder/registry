---
display_name: CloudCLI
description: Run the CloudCLI web interface securely inside a Coder workspace
icon: ../../../../.icons/cloudcli.svg
verified: false
tags: [agent, ai, cloudcli, web]
---

# CloudCLI

Install and run the open source [CloudCLI](https://cloudcli.ai/) web interface for AI coding agents already available in a Coder workspace.

```tf
module "cloudcli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/edd88-pixel/cloudcli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Prerequisites

The workspace image must provide Node.js 22 or newer and npm. Install and authenticate at least one CloudCLI-supported coding agent, such as Claude Code, Cursor CLI, Codex, Gemini CLI, or OpenCode, before using this module. The module reuses those existing agent installations and credentials; it does not install agents or modify their authentication, permissions, settings, or MCP configuration.

For example, install and authenticate Claude Code alongside CloudCLI:

```tf
module "claude-code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.2.0"
  agent_id = coder_agent.main.id

  anthropic_api_key = var.anthropic_api_key
}

module "cloudcli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/edd88-pixel/cloudcli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

See the [Claude Code module](https://registry.coder.com/modules/coder/claude-code) for OAuth and Coder AI Gateway authentication alternatives.

## Security

CloudCLI has access to files and authenticated coding agents inside the workspace. This module therefore:

- binds CloudCLI explicitly to `127.0.0.1`;
- exposes it only through an owner-only Coder app;
- installs the pinned npm package under `$HOME/.coder-modules/edd88-pixel/cloudcli/runtime`;
- stores module-managed logs, runtime data, and process state under `$HOME/.coder-modules/edd88-pixel/cloudcli`.

No public listener, TLS proxy, tunnel, process manager, or nested container runtime is created.

> [!IMPORTANT]
> CloudCLI currently requires Coder's [wildcard access URL](https://coder.com/docs/admin/networking/wildcard-access-url). Its frontend uses root-relative API and WebSocket routes that are not compatible with Coder's path-based app proxy.

> [!NOTE]
> CloudCLI's open source single-user mode currently requires a one-time account setup. The Coder app remains restricted to the workspace owner, but this module does not bypass CloudCLI's authentication.

## Limit project discovery

CloudCLI discovers projects under the workspace user's home directory by default. For a narrower and safer scope, set `workspaces_root` to an absolute path:

```tf
module "cloudcli" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/edd88-pixel/cloudcli/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  workspaces_root = "/home/coder/project"
}
```

The path is validated before it is rendered into the startup script. Relative paths, whitespace, shell metacharacters, and parent-directory components are rejected.

## Troubleshooting

```bash
cat ~/.coder-modules/edd88-pixel/cloudcli/logs/install.log
cat ~/.coder-modules/edd88-pixel/cloudcli/logs/start.log
cat ~/.coder-modules/edd88-pixel/cloudcli/logs/cloudcli.log
```

If startup reports that the configured port is already in use, choose a different `port` or stop the conflicting process. The module never terminates an unrelated listener.

## References

- [CloudCLI prerequisites](https://cloudcli.ai/docs/open-source-self-hosting/prerequisites)
- [CloudCLI environment variables](https://cloudcli.ai/docs/configuration/environment-variables)
- [CloudCLI source](https://github.com/siteboon/claudecodeui)
