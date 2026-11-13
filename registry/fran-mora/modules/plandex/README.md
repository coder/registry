---
display_name: Plandex
description: Install and configure the Plandex CLI AI coding agent in your workspace.
icon: ../../../../.icons/plandex.svg
verified: false
tags: [agent, plandex, ai, cli]
---

# Plandex

Install and configure the [Plandex](https://plandex.ai) CLI AI coding agent in your workspace. Starting Plandex is left to the caller (template command, IDE launcher, or a custom `coder_script`) — the same pattern used by the official `claude-code` module.

```tf
module "plandex" {
  source         = "registry.coder.com/fran-mora/plandex/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = "sk-..."
}
```

## Prerequisites

Plandex needs at least one upstream LLM provider key. Set whichever the user prefers:

- `openai_api_key` — passed to Plandex via `OPENAI_API_KEY`. Default provider.
- `anthropic_api_key` — passed via `ANTHROPIC_API_KEY`.
- `google_api_key` — passed via `GOOGLE_API_KEY`.
- `openrouter_api_key` — passed via `OPENROUTER_API_KEY`.

For a self-hosted Plandex server, also set `plandex_api_host` to the server URL.

## Examples

### Standalone mode with a launcher app

Install Plandex against the user's OpenAI key and add a `coder_app` that opens a Plandex REPL in the workspace from the dashboard.

```tf
locals {
  plandex_workdir = "/home/coder/project"
}

module "plandex" {
  source         = "registry.coder.com/fran-mora/plandex/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  workdir        = local.plandex_workdir
  openai_api_key = "sk-..."
}

resource "coder_app" "plandex" {
  agent_id     = coder_agent.main.id
  slug         = "plandex"
  display_name = "Plandex"
  icon         = "/icon/plandex.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    cd ${local.plandex_workdir}
    plandex
  EOT
}
```

> [!NOTE]
> `coder_app.command` runs when the user clicks the app tile. The module sets the relevant API-key env vars on the agent so the CLI starts pre-authenticated.

### Pin a specific Plandex version

```tf
module "plandex" {
  source          = "registry.coder.com/fran-mora/plandex/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  workdir         = "/home/coder/project"
  plandex_version = "2.2.1"
  openai_api_key  = "sk-..."
}
```

### Self-hosted Plandex server

Point the CLI at a self-hosted Plandex server instead of Plandex Cloud.

```tf
module "plandex" {
  source            = "registry.coder.com/fran-mora/plandex/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  plandex_api_host  = "https://plandex.example.com"
  anthropic_api_key = "sk-ant-..."
}
```

### Skip the installer (Plandex pre-installed in the image)

If Plandex is already baked into the workspace image, set `install_plandex = false` so the module only configures env vars.

```tf
module "plandex" {
  source          = "registry.coder.com/fran-mora/plandex/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  install_plandex = false
  openai_api_key  = "sk-..."
}
```

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `coder exp sync` name of each script it creates via the `scripts` output: an ordered list (`pre_install`, `install`, `post_install`) of names for scripts this module actually creates. Scripts that were not configured are absent from the list.

Downstream `coder_script` resources can wait for this module's install pipeline to finish using `coder exp sync want <self> <each name>`:

```tf
module "plandex" {
  source         = "registry.coder.com/fran-mora/plandex/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder/project"
  openai_api_key = "sk-..."
}

resource "coder_script" "post_plandex" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Plandex install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    trap 'coder exp sync complete post-plandex' EXIT
    coder exp sync want post-plandex ${join(" ", module.plandex.scripts)}
    coder exp sync start post-plandex

    # Your work here runs after plandex finishes installing.
    plandex version
  EOT
}
```

## Troubleshooting

If Plandex doesn't appear on the workspace `PATH` after install, check the install log:

```bash
cat ~/.coder-modules/fran-mora/plandex/logs/install.log
```

The Plandex installer writes the binary to `/usr/local/bin/plandex` if `sudo` is available, otherwise to `$HOME/.local/bin/plandex`. The module ensures the latter is on `PATH` by appending it to the user's shell profiles.

## References

- [Plandex documentation](https://docs.plandex.ai)
- [Plandex GitHub](https://github.com/plandex-ai/plandex)
