---
display_name: Happy
description: Run Happy (slopus/happy) in a Coder workspace and pair your phone to Claude Code with a QR code or direct link.
icon: ../../../../.icons/happy.svg
verified: false
tags: [ai, agent, mobile, claude, coding-agent]
---

# Happy

Runs [Happy](https://github.com/slopus/happy) in a Coder workspace and gives you a single app tile that shows a QR code (and a direct link) for pairing the [Happy mobile/web app](https://happy.engineering) to the Claude Code session running in this workspace, end-to-end encrypted.

Happy wraps `claude` with `happy claude` so you can check on, and take control of, your coding agent from your phone — including push notifications when it needs permission or hits an error.

```tf
module "happy" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/happy/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!IMPORTANT]
> Install and authenticate [Claude Code](https://claude.com/product/claude-code) in the workspace image before using Happy (`claude auth login`) — Happy wraps the `claude` CLI, it doesn't replace it. Happy also needs **tmux** (see [Notes](#notes) — installed automatically in most workspaces, but not guaranteed).

## How pairing works

Happy has no non-interactive pairing mode — the CLI always renders an interactive prompt (choose mobile or web) and, for the mobile flow, a QR code plus a `happy://terminal?...` deep link in the terminal. There's also no way to ask an already-paired machine for a fresh QR without a full re-pair (`happy auth login --force`), which unpairs every previously-linked device.

So this module embraces that: **every time you open the Happy app tile, it mints a brand new pairing link.** Concretely, on each request the module's pairing page:

1. Kills whatever Happy session was running before.
2. Runs `happy auth login --force` (clears any existing pairing) followed by `happy claude`, inside a `tmux` session so Happy gets the real terminal it needs.
3. Drives the interactive prompt itself (auto-selects "Mobile App").
4. Captures the resulting `happy://terminal?...` link and renders it as an actual scannable QR code, plus the link as plain text you can copy — right there on the page, no redirect needed.

Once you scan it (or open the link on your phone), `happy claude` launches for real and keeps running in that `tmux` session — reopening the app tile again later mints a fresh link and disconnects that device, so only do it when you actually want to (re-)pair.

Because of that "every click re-pairs" behavior, keep `share` at its default (`"owner"`) unless you specifically want other people to be able to pair a device to your agent — anyone who can open this app can take it over.

## Examples

### Run Claude Code in a specific project directory

```tf
module "happy" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/gojnimer6553/happy/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
}
```

### Pin the installed version

```tf
module "happy" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/gojnimer6553/happy/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  install_version = "1.2.0"
}
```

### Use a package manager other than npm

```tf
module "happy" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/gojnimer6553/happy/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  package_manager = "bun"
}
```

### Skip installation and use a pre-baked image

```tf
module "happy" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/gojnimer6553/happy/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  install        = false
  install_prefix = "/opt/happy"
}
```

## Notes

- **Requires `tmux`.** Happy's pairing prompt and the wrapped `claude` session both need a real terminal (Ink UI, raw-mode stdin) — there's no headless/non-interactive path, so this module drives it through a real pseudo-terminal via `tmux`. If `tmux` isn't already on `PATH`, the install script installs it automatically via the workspace's system package manager (`apt-get`/`dnf`/`yum`/`apk`/`pacman`) when running as root or with passwordless `sudo`; otherwise it fails with a clear message. For reproducible builds (or if the workspace has neither root nor passwordless `sudo`), add it to your Dockerfile/image instead (e.g. `apt-get install -y tmux`).
- Pairing requires outbound network access to Happy's hosted service (`api.cluster-fluster.com` / `app.happy.engineering` by default) — there's no offline pairing path.
- Happy has no `engines` requirement pinned in its `package.json`; its docs recommend Node.js >= 20. If `node` is not already on `PATH`, the install script bootstraps a pinned Node.js runtime under this module's data directory automatically; override the version with `node_version` if needed.
