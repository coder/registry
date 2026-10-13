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
> If upgrading from v0.x.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI and requires OpenCode 2. The module now only installs and configures OpenCode; launch it with your own `coder_app`. `ai_prompt`, `continue`, `session_id`, and `config_json` are removed, MCP servers move to `mcp`, and `auth_json` now takes the output of `opencode auth export`. See [Migrate from V1](https://opencode.ai/v2/docs/migrate-v1/). Keep using v0.x.x if you depend on Coder Tasks.

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

See the [OpenCode CLI](https://opencode.ai/v2/docs/cli/) for launcher flags such as `--continue`, `--session`, and `--prompt`.

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

`mcp` uses the [`mcp.servers`](https://opencode.ai/v2/docs/mcp-servers/) format. Servers that already exist in `opencode.json` are kept.

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

`auth_json` takes the output of `opencode auth export`. See [OpenCode providers](https://opencode.ai/v2/docs/cli/providers/).

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

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/opencode/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/opencode/logs/install.log
cat ~/.coder-modules/coder-labs/opencode/logs/pre_install.log
cat ~/.coder-modules/coder-labs/opencode/logs/post_install.log
```

See [OpenCode troubleshooting](https://opencode.ai/v2/docs/troubleshooting/).

## References

- [OpenCode documentation](https://opencode.ai/v2/docs/)
- [OpenCode config](https://opencode.ai/v2/docs/config/)
- [OpenCode MCP servers](https://opencode.ai/v2/docs/mcp-servers/)
- [OpenCode CLI](https://opencode.ai/v2/docs/cli/)
- [Migrate from V1](https://opencode.ai/v2/docs/migrate-v1/)
