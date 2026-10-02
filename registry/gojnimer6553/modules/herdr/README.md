---
display_name: Herdr
description: Run Herdr in a Coder workspace and opt in to installing Herdr plugins (e.g. 0cv/herdr-mobile-relay for remote phone control) non-interactively.
icon: ../../../../.icons/herdr.svg
verified: false
tags: [ai, agent, mobile, terminal, herdr]
---

# Herdr

Runs [Herdr](https://herdr.dev) — a terminal/agent-session manager that detects and drives coding
agents (Claude Code, Codex, OpenCode, and others) in persistent background panes — inside a Coder
workspace, and optionally installs Herdr [plugins](https://herdr.dev/docs/plugins/) non-interactively
via `herdr plugin install <spec> --yes`.

```tf
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/herdr/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!IMPORTANT]
> This module installs and starts Herdr, but does not authenticate the coding agent(s) Herdr
> manages (e.g. `claude auth login`) — do that in the workspace image beforehand, same as you would
> without Herdr. Herdr itself needs no account or API key.

> [!IMPORTANT]
> `plugins` only registers plugins with `herdr plugin install --yes` — it does not run a plugin's own
> setup wizard. Most plugins, including [0cv/herdr-mobile-relay](https://github.com/0cv/herdr-mobile-relay),
> still need a one-time interactive step from a workspace terminal afterwards (see
> [How plugin setup works](#how-plugin-setup-works) below). Plugins are third-party, unreviewed content
> pulled from arbitrary GitHub repositories — only list sources you trust.

## How it works

Herdr has no documented headless/daemon startup mode. This module starts `herdr` detached inside its
own `tmux` session, so the server keeps running independent of the `coder_script` that launched it. By
default this is Herdr's default, unnamed session — the same one you get by typing `herdr` in any
workspace terminal — so plugins installed by this module and panes you open by hand end up in the same
place.

On every workspace start, after Herdr comes up, the module runs `herdr plugin install <spec> --yes`
for each entry in `plugins`.

## How plugin setup works

Installing a plugin only registers it with Herdr. Plugins that need their own setup — like
[0cv/herdr-mobile-relay](https://github.com/0cv/herdr-mobile-relay), which needs you to choose a
tunnel/pairing mode — still need that run once from a workspace terminal:

```shell
herdr plugin action invoke setup --plugin herdr-mobile-relay.events
```

(Substitute the plugin's own id — check its `herdr-plugin.toml` — for other plugins.) This module
doesn't drive that wizard automatically: it's interactive by design, asking you to choose between a
temporary and a permanent tunnel.

Once a plugin like `0cv/herdr-mobile-relay` has completed its own setup and is serving a local web UI
(mobile-relay's default is port 8375), set `app_port` to expose it as a Coder app tile — see the
example below.

### Alternative: skip the wizard with `post_start_script`

`0cv/herdr-mobile-relay`'s guided setup only offers two paths, both requiring `cloudflared` — there's
no built-in option to expose the relay through Coder's own app proxy. `post_start_script` can start
the plugin's relay binary directly instead (`$HOME/.local/bin/herdr-mobile-relay serve`, no tunnel
involved) — see
[Expose a plugin's web UI through Coder instead of its own tunnel](#expose-a-plugins-web-ui-through-coder-instead-of-its-own-tunnel)
below.

## Examples

### Install the mobile-relay plugin and expose its pairing UI as an app tile

```tf
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/herdr/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  plugins  = ["0cv/herdr-mobile-relay"]
  app_port = 8375
}
```

The plugin's own setup wizard (see [How plugin setup works](#how-plugin-setup-works)) still needs to
run once from a workspace terminal before the app tile serves anything.

### Expose a plugin's web UI through Coder instead of its own tunnel

`0cv/herdr-mobile-relay` binds to `127.0.0.1:8375` regardless of setup path — the same address
`app_port` already proxies through Coder. `post_start_script` can start the relay binary directly,
skipping the wizard and its `cloudflared` requirement:

```tf
module "herdr" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/gojnimer6553/herdr/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  plugins           = ["0cv/herdr-mobile-relay"]
  app_port          = 8375
  share             = "public" # required: the phone has no Coder session to authenticate with
  post_start_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    MODULE_DIR="$HOME/.coder-modules/gojnimer6553/herdr"
    TOKEN_FILE="$MODULE_DIR/mobile-relay-token"
    PID_FILE="$MODULE_DIR/mobile-relay.pid"
    [ -f "$TOKEN_FILE" ] || openssl rand -hex 16 > "$TOKEN_FILE"
    TOKEN="$(cat "$TOKEN_FILE")"
    # A PID file, not pgrep: pgrep -x can't match a 19-char comm name, and
    # pgrep -f matches this script's own argv (it contains the search text).
    if ! { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2> /dev/null; }; then
      HERDR_RELAY_TOKEN="$TOKEN" nohup herdr-mobile-relay serve \
        >> "$MODULE_DIR/logs/mobile-relay.log" 2>&1 &
      echo $! > "$PID_FILE"
      disown
    fi
    echo "Mobile-relay token: $TOKEN"
    echo "Open this module's 'herdr' app tile to find its public hostname, then from a"
    echo "workspace terminal run:"
    echo "  herdr-mobile-relay setup-fragment \"$TOKEN\" \"$(hostname -s)\" \"wss://<that hostname>\""
    echo "and open https://<that hostname>/#<the printed fragment> on your phone."
  EOT
}
```

This is a workaround: it relies on undocumented plugin internals (the install path and the `serve`
subcommand), not a documented interface. `share = "public"` makes the port reachable by anyone with
the link — the relay's own token and end-to-end encryption are the real access control, not Coder's
session gating.

### Run Herdr's session in a specific project directory

```tf
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/herdr/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
}
```

### Install multiple plugins

```tf
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/herdr/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  plugins = [
    "0cv/herdr-mobile-relay",
    "some-owner/some-other-herdr-plugin",
  ]
}
```

### Skip installation and use a pre-baked image

```tf
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/herdr/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  install  = false
}
```

## Notes

- **Requires `tmux`.** Herdr expects a real pseudo-terminal. The install script installs `tmux`
  automatically (`apt-get`/`dnf`/`yum`/`apk`/`pacman`) when running as root or with passwordless
  `sudo`; otherwise add it to your Dockerfile/image.
- No version pinning: Herdr's installer has no flag for a specific version, so `install = true` always
  installs latest. Set `install = false` and bake a pinned copy into the image for reproducible builds.
- A plugin like `0cv/herdr-mobile-relay` can hold connections to many workspaces' relays in one phone
  app instead of one app per workspace — see that plugin's own docs.
