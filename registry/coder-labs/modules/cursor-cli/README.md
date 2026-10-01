---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Install and configure the Cursor Agent CLI in your workspace.
verified: true
tags: [agent, cursor, ai]
---

# Cursor CLI

Install and configure the [Cursor Agent CLI](https://cursor.com/docs/cli/overview) in your workspace.

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  api_key  = var.cursor_api_key
}
```

> [!WARNING]
> If upgrading from v0.x.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Cursor CLI; launch it with your own `coder_app`. `folder` is renamed to `workdir` and is optional. `model`, `force`, and `ai_prompt` are removed in favor of CLI flags in your launcher. MCP servers are now written to the user-level `~/.cursor/mcp.json` instead of `<folder>/.cursor/mcp.json`. Keep using v0.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  cursor_workdir = "/home/coder/project"
}

module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = local.cursor_workdir
  api_key  = var.cursor_api_key
}

resource "coder_app" "cursor_cli" {
  agent_id     = coder_agent.main.id
  slug         = "cursor-cli"
  display_name = "Cursor CLI"
  icon         = "/icon/cursor.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.cursor_workdir}"
    exec cursor-agent --model gpt-5 --force
  EOT
}
```

When `workdir` is set, the module creates it if missing and marks it as a trusted workspace, so Cursor CLI does not show the trust prompt there. Pass `--model`, `--force`, `--approve-mcps`, or any other [CLI flag](https://cursor.com/docs/cli/reference/parameters) in the launcher command.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for interactive `cursor-agent`, but one-shot commands like `cursor-agent -p` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### MCP servers and rules

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
  api_key  = var.cursor_api_key

  mcp = jsonencode({
    mcpServers = {
      playwright = {
        command = "npx"
        args    = ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
      }
    }
  })

  rules_files = {
    "python.mdc" = <<-EOT
      ---
      description: Python conventions
      alwaysApply: true
      ---

      - Use type hints on public functions.
    EOT
  }
}
```

`mcp` is merged into the user-level `~/.cursor/mcp.json`, so the servers apply to every Cursor CLI session in the workspace. Servers already in that file win on duplicate names, so edits made inside the workspace are never overwritten. `rules_files` are written to `<workdir>/.cursor/rules/` and require `workdir`.

> [!NOTE]
> The official installer ships a self-contained binary and does not install Node.js. MCP servers whose `command` is `npx` or `uvx` need that runtime available in the workspace image, or installed with `pre_install_script`.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "post_cursor_cli" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Cursor CLI install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-cursor-cli' EXIT
    coder exp sync want post-cursor-cli ${join(" ", module.cursor_cli.scripts)}
    coder exp sync start post-cursor-cli

    cursor-agent --version
  EOT
}
```

## Configuration

When `api_key` is set, it is exported as `CURSOR_API_KEY` and is not rendered into the install script. To create a key, see [Cursor CLI authentication](https://cursor.com/docs/cli/reference/authentication). Without a key, run `cursor-agent login` in the workspace.

The module always installs the latest Cursor CLI with the [official installer](https://cursor.com/install) and skips the install when `cursor-agent` is already on `PATH`. If `install_cursor_cli = false`, a working `cursor-agent` must already be available on `PATH`, or workspace startup fails.

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/cursor-cli/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/cursor-cli/logs/install.log
cat ~/.coder-modules/coder-labs/cursor-cli/logs/pre_install.log
cat ~/.coder-modules/coder-labs/cursor-cli/logs/post_install.log
```

## References

- [Cursor CLI documentation](https://cursor.com/docs/cli/overview)
- [Cursor CLI MCP](https://cursor.com/docs/cli/mcp)
- [Cursor rules](https://cursor.com/docs/context/rules)
