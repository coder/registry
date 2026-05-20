---
display_name: Codex CLI
icon: ../../../../.icons/openai.svg
description: Install and configure the Codex CLI in your workspace.
verified: true
tags: [agent, codex, ai, openai, ai-gateway]
---

# Codex CLI

Install and configure the [Codex CLI](https://github.com/openai/codex) in your workspace.

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = var.openai_api_key
}
```

> [!WARNING]
> If upgrading from v4.x.x of this module: v5 is a major refactor that drops support for [Coder Tasks](https://coder.com/docs/ai-coder/tasks) and [Boundary](https://coder.com/docs/ai-coder/agent-firewall). v5 also assumes npm is pre-installed; it no longer bootstraps Node.js. Keep using v4.x.x if you depend on them. See the [PR description](https://github.com/coder/registry/pull/879) for a full migration guide.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  codex_workdir = "/home/coder/project"
}

module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  workdir        = local.codex_workdir
  openai_api_key = var.openai_api_key
}

resource "coder_app" "codex" {
  agent_id     = coder_agent.main.id
  slug         = "codex"
  display_name = "Codex"
  icon         = "/icon/openai.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    cd "${local.codex_workdir}"
    codex
  EOT
}
```

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for interactive `codex` (which stays alive), but one-shot commands like `codex exec` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (e.g. via tmux/screen).

### Usage with AI Gateway

[AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) is a Premium Coder feature that provides centralized LLM proxy management. Requires Coder >= 2.30.0.

```tf
module "codex" {
  source            = "registry.coder.com/coder-labs/codex/coder"
  version           = "5.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  enable_ai_gateway = true
}
```

When `enable_ai_gateway = true`, the module configures Codex to use the `aigateway` model provider in `config.toml` with the workspace owner's session token for authentication.

> [!CAUTION]
> `enable_ai_gateway = true` is mutually exclusive with `openai_api_key`. Setting both fails at plan time.

> [!NOTE]
> If you provide a custom `base_config_toml`, the module writes it verbatim and does not inject `model_provider = "aigateway"` automatically. Add it to your config yourself:
>
> ```toml
> model_provider = "aigateway"
> ```

### Advanced Configuration

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder/project"
  openai_api_key = var.openai_api_key

  codex_version = "0.128.0"

  base_config_toml = <<-EOT
    sandbox_mode = "danger-full-access"
    approval_policy = "never"
    preferred_auth_method = "apikey"
  EOT

  mcp = <<-EOT
    [mcp_servers.GitHub]
    command = "npx"
    args = ["-y", "@modelcontextprotocol/server-github"]
    type = "stdio"
  EOT
}
```

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = var.openai_api_key
}

resource "coder_script" "post_codex" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Codex install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    trap 'coder exp sync complete post-codex' EXIT
    coder exp sync want post-codex ${join(" ", module.codex.scripts)}
    coder exp sync start post-codex

    codex --version
  EOT
}
```

## Configuration

When no custom `base_config_toml` is provided, the module uses a minimal default with `preferred_auth_method = "apikey"`. For advanced options, see [Codex config docs](https://developers.openai.com/codex/config-advanced).

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/codex/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/codex/logs/install.log
cat ~/.coder-modules/coder-labs/codex/logs/pre_install.log
cat ~/.coder-modules/coder-labs/codex/logs/post_install.log
```

## References

- [Codex CLI Documentation](https://github.com/openai/codex)
- [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway)
