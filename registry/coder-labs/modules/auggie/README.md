---
display_name: Auggie CLI
icon: ../../../../.icons/auggie.svg
description: Install and configure Augment's Auggie CLI in your workspace.
verified: true
tags: [agent, auggie, ai, augment]
---

# Auggie CLI

Install and configure [Auggie CLI](https://docs.augmentcode.com/cli/overview) in your workspace. Auggie is installed with npm, so Node.js 20+ and npm must be available in the image or installed with `pre_install_script`.

```tf
module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!WARNING]
> If upgrading from v0.x.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Auggie; launch it with your own `coder_app`. `folder` is renamed to `workdir` and is optional. `ai_prompt`, `continue_previous_conversation`, `interaction_mode`, `report_tasks`, `order`, `group`, `cli_app`, `web_app_display_name`, `cli_app_display_name`, `install_agentapi`, and `agentapi_version` are removed in favor of CLI flags in your launcher. `mcp` and `mcp_files` servers are now added to `~/.augment/settings.json`, `rules` are written to `~/.augment/rules/coder-module.md`, and `auggie_model` sets the `model` key in `~/.augment/settings.json`. Keep using v0.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  auggie_workdir = "/home/coder/project"
}

module "auggie" {
  source                = "registry.coder.com/coder-labs/auggie/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  workdir               = local.auggie_workdir
  augment_session_token = var.augment_session_token
}

resource "coder_app" "auggie" {
  agent_id     = coder_agent.main.id
  slug         = "auggie"
  display_name = "Auggie"
  icon         = "/icon/auggie.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.auggie_workdir}"
    exec auggie --continue
  EOT
}
```

See [CLI flags](https://docs.augmentcode.com/cli/reference) for launcher options such as `--continue`, `--model`, `--print`, and `--quiet`.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for interactive `auggie`, but one-shot commands like `auggie --print` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### MCP servers and rules

```tf
module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  mcp = jsonencode({
    mcpServers = {
      filesystem = {
        command = "npx"
        args    = ["-y", "@modelcontextprotocol/server-filesystem", "/home/coder/project"]
      }
    }
  })
  mcp_files = ["/home/coder/.config/mcp/servers.json"]

  rules = <<-EOT
    # Project Guidelines

    - Use TypeScript for all new JavaScript files.
    - Write unit tests for all new functions.
  EOT
}
```

`mcp` and `mcp_files` use the [`mcpServers`](https://docs.augmentcode.com/cli/integrations#mcp-integrations) format and are added with `auggie mcp add-json`; servers that already exist are kept. `rules` are loaded as [user rules](https://docs.augmentcode.com/cli/rules). To pick a default model, set `auggie_model` to a name from `auggie models list`.

### Pinned version

```tf
module "auggie" {
  source         = "registry.coder.com/coder-labs/auggie/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  auggie_version = "0.36.0"
}
```

Auggie updates itself in interactive mode unless [automatic updates](https://docs.augmentcode.com/cli/autoupgrade) are disabled.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "auggie" {
  source   = "registry.coder.com/coder-labs/auggie/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "post_auggie" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Auggie install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-auggie' EXIT
    coder exp sync want post-auggie ${join(" ", module.auggie.scripts)}
    coder exp sync start post-auggie

    auggie --version
  EOT
}
```

## Authentication

`augment_session_token` takes the session JSON printed by `auggie token print` and is exported as `AUGMENT_SESSION_AUTH`. Without it, run `auggie login` in the workspace. See [Auggie authentication](https://docs.augmentcode.com/cli/setup-auggie/authentication).

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/auggie/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/auggie/logs/install.log
cat ~/.coder-modules/coder-labs/auggie/logs/pre_install.log
cat ~/.coder-modules/coder-labs/auggie/logs/post_install.log
```

## References

- [Auggie CLI documentation](https://docs.augmentcode.com/cli/overview)
- [Auggie CLI flags](https://docs.augmentcode.com/cli/reference)
- [Auggie MCP integrations](https://docs.augmentcode.com/cli/integrations)
- [Auggie rules](https://docs.augmentcode.com/cli/rules)
