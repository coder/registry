---
display_name: Amp
icon: ../../../../.icons/sourcegraph-amp.svg
description: Install and configure the Amp CLI in your workspace.
verified: true
tags: [agent, sourcegraph, amp, ai]
---

# Amp

Install and configure the [Amp CLI](https://ampcode.com/docs/cli) in your workspace.

```tf
module "amp" {
  source      = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version     = "4.0.0"
  agent_id    = coder_agent.main.id
  amp_api_key = var.amp_api_key
}
```

> [!WARNING]
> If upgrading from v3.x.x of this module: v4 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Amp; launch it with your own `coder_app`. `workdir` is now optional. `ai_prompt`, `mode`, `report_tasks`, `install_via_npm`, and the web/CLI app inputs are removed; pass `--mode` in your launcher instead. `base_amp_config` is replaced by `amp_settings`, which merges keys into `~/.config/amp/settings.json` instead of overwriting the file and no longer writes default keys. `mcp` servers are merged without overriding servers already on disk, and the Coder task-reporting MCP server is no longer added. `instruction_prompt` is now written to `~/.config/amp/AGENTS.md`. Keep using v3.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  amp_workdir = "/home/coder/project"
}

module "amp" {
  source      = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version     = "4.0.0"
  agent_id    = coder_agent.main.id
  workdir     = local.amp_workdir
  amp_api_key = var.amp_api_key
}

resource "coder_app" "amp" {
  agent_id     = coder_agent.main.id
  slug         = "amp"
  display_name = "Amp"
  icon         = "/icon/sourcegraph-amp.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.amp_workdir}"
    exec amp --mode medium
  EOT
}
```

When `workdir` is set, the module creates it if missing. Pass `--mode` (`low`, `medium`, `high`, `ultra`) or any other flag from `amp --help` in the launcher command. See [The Dial](https://ampcode.com/docs/the-dial) for how modes work.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for interactive `amp`, but one-shot commands like `amp -x` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### Settings, MCP servers, and guidance

```tf
module "amp" {
  source      = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version     = "4.0.0"
  agent_id    = coder_agent.main.id
  workdir     = "/home/coder/project"
  amp_api_key = var.amp_api_key

  amp_settings = jsonencode({
    "amp.git.commit.coauthor.enabled" = true
    "amp.permissions" = [
      { tool = "Bash", action = "ask", matches = { cmd = ["git push*"] } }
    ]
  })

  mcp = jsonencode({
    playwright = {
      command = "npx"
      args    = ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
    }
  })

  instruction_prompt = <<-EOT
    # Instructions
    - Run the test suite before committing.
  EOT
}
```

`amp_settings` and `mcp` are merged into the user-level `~/.config/amp/settings.json` (or `$AMP_SETTINGS_FILE` when set). Keys in `amp_settings` are rewritten on every start; all other keys in the file are preserved. Servers already under `amp.mcpServers` win on duplicate names, matching `amp mcp add`, so edits made inside the workspace are never overwritten. If the file contains comments or trailing commas, the module leaves it unchanged and logs a warning. See [Amp configuration](https://ampcode.com/docs/cli/settings) and [MCP](https://ampcode.com/docs/customize/mcp).

`instruction_prompt` is written to `~/.config/amp/AGENTS.md`, which Amp includes in every session. See [AGENTS.md](https://ampcode.com/docs/customize/agents-md).

> [!NOTE]
> The official installer ships a self-contained binary and does not install Node.js. MCP servers whose `command` is `npx` or `uvx` need that runtime available in the workspace image, or installed with `pre_install_script`.

### Managed settings

```tf
module "amp" {
  source      = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version     = "4.0.0"
  agent_id    = coder_agent.main.id
  amp_version = "0.0.1790769659-g954f35"

  managed_settings = {
    "amp.updates.mode" = "disabled"
    "amp.mcpPermissions" = [
      { matches = { url = "*" }, action = "reject" }
    ]
  }
}
```

`managed_settings` is written as root to `/etc/ampcode/managed-settings.json`. Amp merges it over user and workspace settings: scalar values from this file win, lists are combined, and objects are merged key by key. See [Enterprise managed settings](https://ampcode.com/docs/cli/settings#enterprise-managed-settings).

Amp updates itself in the background by default, so pin `amp_version` together with `"amp.updates.mode" = "disabled"` (or the `AMP_SKIP_UPDATE_CHECK=1` environment variable) to stay on that version.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "amp" {
  source   = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version  = "4.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "post_amp" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Amp install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-amp' EXIT
    coder exp sync want post-amp ${join(" ", module.amp.scripts)}
    coder exp sync start post-amp

    amp --version
  EOT
}
```

## Configuration

When `amp_api_key` is set, it is exported as `AMP_API_KEY` and is not rendered into the install script. Create an access token (it starts with `sgamp_`) in [Amp settings](https://ampcode.com/settings/security#access-token). Without a key, run `amp login` in the workspace.

The module installs Amp with the [official installer](https://ampcode.com/install.sh) into `~/.amp/bin` and links it into `~/.local/bin`. The install is skipped when `amp` is already on `PATH` and matches `amp_version` (or `amp_version` is empty). If `install_amp = false`, a working `amp` must already be available on `PATH`, or workspace startup fails.

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/sourcegraph-amp/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/sourcegraph-amp/logs/install.log
cat ~/.coder-modules/coder-labs/sourcegraph-amp/logs/pre_install.log
cat ~/.coder-modules/coder-labs/sourcegraph-amp/logs/post_install.log
```

## References

- [Amp CLI documentation](https://ampcode.com/docs/cli)
- [Amp configuration](https://ampcode.com/docs/cli/settings)
- [Amp MCP](https://ampcode.com/docs/customize/mcp)
