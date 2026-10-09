---
display_name: OpenCode
icon: ../../../../.icons/opencode.svg
description: Install and configure the OpenCode AI coding agent in your workspace.
verified: false
tags: [agent, opencode, ai]
---

# OpenCode

Install and configure [OpenCode](https://opencode.ai) in your workspace.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!WARNING]
> If upgrading from v0.x.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures OpenCode; launch it with your own `coder_app`. `workdir` is now optional. `ai_prompt`, `continue`, and `session_id` are removed in favor of the `--prompt`, `--continue`, and `--session` CLI flags in your launcher. `config_json` is now merged into `~/.config/opencode/opencode.json` instead of replacing it, and MCP servers move from `config_json` to the new `mcp` variable. `auth_json` is merged into `auth.json` instead of replacing it. Keep using v0.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  opencode_workdir = "/home/coder/project"
}

module "opencode" {
  source    = "registry.coder.com/coder-labs/opencode/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  workdir   = local.opencode_workdir
  auth_json = var.opencode_auth_json

  config_json = jsonencode({
    model = "anthropic/claude-sonnet-4-5"
  })
}

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  icon         = "/icon/opencode.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.opencode_workdir}"
    exec opencode --continue
  EOT
}
```

When `workdir` is set, the module creates it if missing. Pass `--model`, `--continue`, `--session`, `--agent`, or any other [CLI flag](https://opencode.ai/docs/cli/) in the launcher command.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for the interactive `opencode` TUI, but one-shot commands like `opencode run` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux or `opencode attach`).

### MCP servers

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  mcp = jsonencode({
    playwright = {
      type    = "local"
      command = ["npx", "-y", "@playwright/mcp@latest", "--headless", "--isolated"]
      enabled = true
    }
    context7 = {
      type = "remote"
      url  = "https://mcp.context7.com/mcp"
    }
  })
}
```

`mcp` uses the format of the [`mcp` key in `opencode.json`](https://opencode.ai/docs/mcp-servers/) and is merged into `~/.config/opencode/opencode.json`. Servers already in that file win on duplicate names, so changes made inside the workspace (for example with `opencode mcp add`) are not overwritten.

> [!NOTE]
> The official installer ships a self-contained binary and does not install Node.js. MCP servers whose `command` is `npx` or `uvx` need that runtime available in the workspace image, or installed with `pre_install_script`.

### Managed settings

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  managed_settings = {
    share      = "disabled"
    autoupdate = false
    permission = {
      bash = "ask"
    }
  }
}
```

`managed_settings` is written as root to `/etc/opencode/opencode.json`. OpenCode loads [managed settings](https://opencode.ai/docs/config/#managed-settings) last, so user and project config cannot override them. Writing the file requires root or passwordless `sudo`; otherwise the module logs a warning and skips it.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "post_opencode" {
  agent_id     = coder_agent.main.id
  display_name = "Run after OpenCode install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-opencode' EXIT
    coder exp sync want post-opencode ${join(" ", module.opencode.scripts)}
    coder exp sync start post-opencode

    opencode --version
  EOT
}
```

## Configuration

`config_json` is deep-merged into the global `~/.config/opencode/opencode.json`: keys you set win, and everything else in the file is preserved. If the existing file is not valid JSON (for example, JSONC with comments), it is backed up to `opencode.json.bak` and replaced. See the [OpenCode config reference](https://opencode.ai/docs/config/) for available keys.

`auth_json` uses the format of `~/.local/share/opencode/auth.json` (the file `opencode providers login` writes). Its provider entries are merged into that file with mode `0600`, and other credentials on disk are preserved. The value is exported to the workspace as `CODER_OPENCODE_AUTH_JSON` so it is never rendered into the install script. Alternatively, skip `auth_json` and set the provider's API key environment variable (for example `ANTHROPIC_API_KEY`) with a `coder_env`. See [OpenCode providers](https://opencode.ai/docs/providers/).

The module installs OpenCode with the [official installer](https://opencode.ai/install) into `~/.opencode/bin`. Set `opencode_version` to pin a release; when a different version is already installed, the installer runs again. With `latest`, the install is skipped when `opencode` is already on `PATH`. OpenCode updates itself on startup by default; set `autoupdate = false` in `config_json` or `managed_settings` to keep a pinned version. If `install_opencode = false`, a working `opencode` must already be available on `PATH`, or workspace startup fails.

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/opencode/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/opencode/logs/install.log
cat ~/.coder-modules/coder-labs/opencode/logs/pre_install.log
cat ~/.coder-modules/coder-labs/opencode/logs/post_install.log
```

Run `opencode debug config` in the workspace to see the resolved configuration.

## References

- [OpenCode documentation](https://opencode.ai/docs)
- [OpenCode config](https://opencode.ai/docs/config/)
- [OpenCode MCP servers](https://opencode.ai/docs/mcp-servers/)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
