---
display_name: OpenCode Server
description: Run OpenCode 1.x as a password-protected headless server and attach to it from your laptop or the browser.
icon: ../../../../.icons/opencode.svg
verified: false
tags: [agent, opencode, ai, server]
---

# OpenCode Server

Runs [OpenCode](https://opencode.ai) 1.x in [server mode](https://opencode.ai/docs/server/) (`opencode serve`) inside the workspace, so the agent, its sessions, and its tools live next to your code while you drive it from a local terminal with `opencode attach`.

```tf
module "opencode_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/opencode-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/src"
}
```

- Installs OpenCode 1.x with the official installer (skipped if the requested version is already installed).
- Starts `opencode serve` on `127.0.0.1:4096` with HTTP basic auth. The password is generated once and stored in `~/.config/opencode/server-password`.
- Adds an **OpenCode** terminal app that attaches to the same server, so browser and laptop clients share sessions.

This module targets OpenCode 1.x. For OpenCode 2, use [`coder-labs/opencode`](https://registry.coder.com/modules/coder-labs/opencode).

## Connect from your laptop

Install an OpenCode 1.x client locally, then:

```sh
WORKSPACE=my-workspace
coder port-forward "$WORKSPACE" --tcp 4096:4096 &
export OPENCODE_SERVER_PASSWORD="$(coder ssh "$WORKSPACE" -- cat .config/opencode/server-password)"
opencode attach http://127.0.0.1:4096 --dir /home/coder/src
```

## Examples

### Route models through Coder AI Gateway

Writes an `opencode.json` that points the Anthropic and OpenAI providers at this deployment's [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway), authenticated with the workspace owner's session token. The token reaches OpenCode through an environment variable and is never written to disk. An existing `opencode.json` is left alone.

```tf
module "opencode_server" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/droopy4096/opencode-server/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/src"
  enable_ai_gateway = true
}
```

### Pin a version and manage the config

`config_json` overwrites the global `opencode.json` on every start.

```tf
module "opencode_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/opencode-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  opencode_version = "1.19.5"
  config_json = jsonencode({
    "$schema"  = "https://opencode.ai/config.json"
    autoupdate = false # keep the pinned version
  })
}
```

### Serve several projects

Run one server per project on different ports and turn off the extra apps:

```tf
module "opencode_api" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/opencode-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/src/api"
  port     = 4097
  web_app  = false
}
```

## Security

- The server listens on loopback only by default. Reach it through `coder port-forward` or the bundled app instead of exposing `hostname = "0.0.0.0"`.
- Anyone with the password can run commands in the workspace through the server API. The password file is `0600` and lives in your home directory.

## Troubleshooting

Logs live in `~/.coder-modules/droopy4096/opencode-server/logs/` (`install.log`, `start.log`, `server.log`).
