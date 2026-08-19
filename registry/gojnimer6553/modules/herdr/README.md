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

Herdr has no documented headless/daemon startup mode (like most terminal multiplexers, it expects a
real tty). This module gives it one the same way the [`happy`](../happy) module does for the `happy`
CLI: it starts `herdr` detached inside its own `tmux` session, so the server keeps running in the
background independent of the `coder_script` that launched it. By default this runs Herdr's default,
unnamed session — the same one you get by typing `herdr` in any workspace terminal — so plugins
installed by this module and panes you open by hand end up in the same place.

On every workspace start, after Herdr comes up, the module runs `herdr plugin install <spec> --yes`
for each entry in `plugins`.

## How plugin setup works

Installing a plugin (via this module's `plugins` variable, or by hand) only registers it with Herdr.
Plugins that need their own setup — like
[0cv/herdr-mobile-relay](https://github.com/0cv/herdr-mobile-relay), which needs you to choose a
tunnel/pairing mode — still need that run once from a workspace terminal:

```shell
herdr plugin action invoke setup --plugin herdr-mobile-relay.events
```

(Substitute the plugin's own id — check its `herdr-plugin.toml` — for other plugins.) This module
deliberately does not attempt to drive that wizard automatically: it's interactive by design (it asks
you to choose between a temporary tunnel and a permanent one, and confirms installing tools like
`cloudflared`), and scripting around it reliably wasn't something this module could verify without a
live Herdr install to test against.

Once a plugin like `0cv/herdr-mobile-relay` has completed its own setup and is serving a local web UI
(mobile-relay's default is port 8375), set `app_port` to expose it as a Coder app tile — see the
example below.

### Alternative: skip the wizard entirely with `post_start_script`

`0cv/herdr-mobile-relay`'s guided setup (`herdr plugin action invoke setup ...`) only offers two
paths, and both hard-require `cloudflared` — there's no option to expose the relay through Coder's
own app proxy instead. If you don't want a Cloudflare account/tunnel in the workspace at all, you can
bypass the wizard and start the plugin's own relay binary directly from `post_start_script`, since it
installs to `$HOME/.local/bin/herdr-mobile-relay` (on `PATH` by the time `post_start_script` runs) and
accepts a `serve` subcommand with no tunnel involved — see
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

`0cv/herdr-mobile-relay` binds to `127.0.0.1:8375` by default regardless of which setup path you use —
the same address `app_port` already proxies through Coder. `post_start_script` can start the relay
binary directly (`herdr-mobile-relay serve`), skipping the wizard and its `cloudflared` requirement
entirely:

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
    # A PID file, not pgrep: "herdr-mobile-relay" is 19 characters, past
    # Linux's 15-character comm-name limit, so "pgrep -x" can never match it
    # (silently -- procps only warns on stderr). "pgrep -f" has the opposite
    # problem: the whole post_start_script text is itself the argv of the
    # "bash -c" process running it, and that text literally contains
    # "herdr-mobile-relay serve", so an -f/substring match would match this
    # very script's own process and skip starting the relay on every run.
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

This is a workaround, not something the plugin documents or the coder-utils/coder-registry-guaranteed
contract of this module covers: it relies on the plugin's binary continuing to install to
`$HOME/.local/bin/herdr-mobile-relay` and accepting an undocumented (but source-confirmed) `serve`
subcommand. `share = "public"` makes the port reachable by anyone with the link, same as a Cloudflare
Tunnel would — Herdr's own relay token and end-to-end encryption remain the real access control, not
Coder's `owner`/`authenticated` gating (which a phone with no Coder session can't satisfy anyway).

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

- **Requires `tmux`.** Same reasoning as the [`happy`](../happy) module: Herdr expects a real
  pseudo-terminal and has no non-interactive/daemon startup path, so this module drives it through
  one via `tmux`. If `tmux` isn't already on `PATH`, the start script installs it automatically via
  the workspace's system package manager (`apt-get`/`dnf`/`yum`/`apk`/`pacman`) when running as root
  or with passwordless `sudo`; otherwise it fails with a clear message. For reproducible builds (or if
  the workspace has neither root nor passwordless `sudo`), add it to your Dockerfile/image instead.
- No version pinning: Herdr's installer (`herdr.dev/install.sh`) has no documented flag for
  installing a specific version as of this writing, so `install = true` always installs whatever it
  currently serves as latest. Set `install = false` and bake a pinned copy into the workspace image if
  you need reproducible versions.
- Multi-workspace fan-in: a plugin like `0cv/herdr-mobile-relay` is designed so its own phone/web app
  can hold connections to many independent relays at once (one per workspace) rather than one app
  instance per workspace — see that plugin's own docs for how to add a workspace's relay to an
  existing installed app instead of minting a new one.
