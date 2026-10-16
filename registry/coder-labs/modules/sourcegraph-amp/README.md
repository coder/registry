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
> If upgrading from v3.x.x of this module: v4 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Amp; launch it with your own `coder_app`. `ai_prompt`, `mode`, `report_tasks`, `install_via_npm`, and the web/CLI app inputs are removed; pass `--mode` in your launcher instead. `base_amp_config` no longer writes default keys, and the Coder task-reporting MCP server is no longer added. Keep using v3.x.x if you depend on Coder Tasks.

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

### Settings, MCP servers, and guidance

```tf
module "amp" {
  source      = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version     = "4.0.0"
  agent_id    = coder_agent.main.id
  workdir     = "/home/coder/project"
  amp_api_key = var.amp_api_key

  base_amp_config = <<-EOF
  {
    "amp.git.commit.coauthor.enabled": true,
    "amp.permissions": [
      {
        "tool": "Bash",
        "action": "ask",
        "matches": {
          "cmd": ["git push*"]
        }
      }
    ]
  }
  EOF

  mcp = <<-EOF
  {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
    }
  }
  EOF

  instruction_prompt = <<-EOT
    # Instructions
    - Run the test suite before committing.
  EOT
}
```

`base_amp_config` uses the [Amp settings](https://ampcode.com/docs/cli/settings) format and overwrites `~/.config/amp/settings.json` on every start. `mcp` uses the [`amp.mcpServers`](https://ampcode.com/docs/customize/mcp) format and is added after it. `instruction_prompt` is written to `~/.config/AGENTS.md` ([AGENTS.md](https://ampcode.com/docs/customize/agents-md)).

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

## Authentication

Set `amp_api_key` (exported as `AMP_API_KEY`) or run `amp login` in the workspace. See [Amp CLI](https://ampcode.com/docs/cli).

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
