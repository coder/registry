---
display_name: OpenCode
icon: ../../../../.icons/opencode.svg
description: Install and configure the OpenCode AI coding agent in your workspace.
verified: false
tags: [agent, opencode, ai]
---

# OpenCode

Install and configure [OpenCode 2](https://opencode.ai/v2/docs/) in your workspace.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!WARNING]
> If upgrading from v0.x.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures OpenCode; launch it with your own `coder_app`. `workdir` is now optional. `ai_prompt`, `continue`, and `session_id` are removed in favor of the `--prompt`, `--continue`, and `--session` CLI flags in your launcher. The module now installs OpenCode 2 and requires it. `config_json` is merged into the global `opencode.json` instead of replacing it, MCP servers move from `config_json` to the new `mcp` variable (written under `mcp.servers`), and `auth_json` now takes the output of `opencode auth export` instead of `auth.json` contents. Keep using v0.x.x if you depend on Coder Tasks.

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

When `workdir` is set, the module creates it if missing. Pass `--continue`, `--session`, `--prompt`, `--auto`, or any other flag from `opencode --help` in the launcher command, or launch the minimal interface with `opencode mini`. See the [OpenCode CLI](https://opencode.ai/v2/docs/cli/).

> [!CAUTION]
> `--auto` approves every permission request that is not explicitly denied, including shell commands. Use it only in trusted environments.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for the interactive `opencode` TUI, but one-shot commands like `opencode run` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

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
    }
    context7 = {
      type     = "remote"
      url      = "https://mcp.context7.com/mcp"
      disabled = true
    }
  })
}
```

`mcp` maps server names to server objects in the format of [`mcp.servers`](https://opencode.ai/v2/docs/mcp-servers/) and is merged into the global `opencode.json` under `mcp.servers`. Servers connect automatically; set `disabled = true` to keep one configured without connecting it. Do not use the V1 `enabled` field: OpenCode 2 ignores it inside `mcp.servers`, so the server still connects. Servers already in the file win on duplicate names, including V1-style entries listed directly under `mcp`, so changes made inside the workspace (for example with `opencode mcp add --global`) are not overwritten.

> [!NOTE]
> The official installer ships a self-contained binary and does not install Node.js. MCP servers whose `command` is `npx` or `uvx` need that runtime available in the workspace image, or installed with `pre_install_script`.

### Policies

OpenCode 2 has no system-wide managed settings file. Use [policies](https://opencode.ai/v2/docs/policies/) in `config_json` to deny providers or hard-deny permission checks. Policies in the global config override project config, so a repository cannot re-enable a provider you deny here.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  config_json = jsonencode({
    experimental = {
      policies = [
        { action = "provider.use", resource = "*", effect = "deny" },
        { action = "provider.use", resource = "anthropic", effect = "allow" },
        { action = "permission", resource = "shell:git push *", effect = "deny" },
      ]
    }
  })
}
```

> [!NOTE]
> The global config is owned by the workspace user, so these policies guard against project config, not against the user. For organization-enforced policy, use a connected [OpenCode Console](https://opencode.ai/v2/docs/policies/#console) workspace.

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

`config_json` is deep-merged into the global `opencode.json` in `$OPENCODE_CONFIG_DIR`, else `$XDG_CONFIG_HOME/opencode`, else `~/.config/opencode`. Keys you set win, and everything else in the file is preserved. If the existing file is not valid JSON (for example, JSONC with comments), it is backed up to `opencode.json.bak` and replaced. When OpenCode's shared background service is already running, the module runs `opencode reload` so the change takes effect. See the [OpenCode config reference](https://opencode.ai/v2/docs/config/) for available keys.

OpenCode 2 stores credentials in its SQLite database, not in `auth.json`. `auth_json` takes the JSON array printed by `opencode auth export` and is applied with `opencode auth import`. Credentials with the same `id` are replaced on every start so rotated secrets apply, and other saved accounts are preserved. The value is exported to the workspace as `CODER_OPENCODE_AUTH_JSON` so it is never rendered into the install script.

```tf
module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  auth_json = jsonencode([{
    id            = "coder-anthropic"
    integrationID = "anthropic"
    label         = "coder"
    active        = true
    value         = { type = "key", key = var.anthropic_api_key }
  }])
}
```

Alternatively, skip `auth_json` and set the provider's API key environment variable (for example `ANTHROPIC_API_KEY`) with a `coder_env`. OpenCode lists it as an environment connection. See [OpenCode providers](https://opencode.ai/v2/docs/cli/providers/).

The module installs OpenCode 2 with the [official installer](https://opencode.ai/v2/install) into `~/.opencode/bin`, retrying when the installer cannot resolve the latest release. Set `opencode_version` to pin a release; when a different version or OpenCode 1 is already installed, the installer runs again. With `latest`, the install is skipped when OpenCode 2 is already on `PATH`. OpenCode checks for updates by default; set `update = "disable"` in `config_json` to keep a pinned version. If `install_opencode = false`, a working OpenCode 2 `opencode` must already be available on `PATH`, or workspace startup fails.

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/opencode/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/opencode/logs/install.log
cat ~/.coder-modules/coder-labs/opencode/logs/pre_install.log
cat ~/.coder-modules/coder-labs/opencode/logs/post_install.log
```

Run `opencode debug config` in the workspace to see the resolved configuration, and `opencode service status` to check the background service. OpenCode's own logs are in `~/.local/share/opencode/log/opencode.log`. See [OpenCode troubleshooting](https://opencode.ai/v2/docs/troubleshooting/).

## References

- [OpenCode documentation](https://opencode.ai/v2/docs/)
- [OpenCode config](https://opencode.ai/v2/docs/config/)
- [OpenCode MCP servers](https://opencode.ai/v2/docs/mcp-servers/)
- [OpenCode policies](https://opencode.ai/v2/docs/policies/)
- [OpenCode CLI](https://opencode.ai/v2/docs/cli/)
- [Migrate from V1](https://opencode.ai/v2/docs/migrate-v1/)
