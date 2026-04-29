---
display_name: Codex CLI
icon: ../../../../.icons/openai.svg
description: Install and configure the Codex CLI in your workspace.
verified: true
tags: [agent, codex, ai, openai, ai-gateway]
---

# Codex CLI

Install and configure the [Codex CLI](https://github.com/openai/codex) in your workspace. Starting Codex is left to the caller (template command, IDE launcher, or a custom `coder_script`).

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = var.openai_api_key
}
```

> [!WARNING]
> If upgrading from v4.x.x of this module: v5 is a major refactor that drops support for [Coder Tasks](https://coder.com/docs/ai-coder/tasks) and [Boundary](https://coder.com/docs/ai-coder/agent-firewall). Keep using v4.x.x if you depend on them.

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
    cd ${local.codex_workdir}
    codex
  EOT
}
```

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

When `enable_ai_gateway = true`, the module configures Codex to use the `aibridge` model provider in `config.toml` with the workspace owner's session token for authentication.

> [!CAUTION]
> `enable_ai_gateway = true` is mutually exclusive with `openai_api_key`. Setting both fails at plan time.

> [!NOTE]
> If you provide a custom `base_config_toml`, the module writes it verbatim and does not inject `model_provider = "aibridge"` automatically. Add it to your config yourself:
>
> ```toml
> model_provider = "aibridge"
> ```

### Advanced Configuration

```tf
module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  workdir        = "/home/coder/project"
  openai_api_key = var.openai_api_key

  codex_version = "0.1.0"

  base_config_toml = <<-EOT
    sandbox_mode = "danger-full-access"
    approval_policy = "never"
    preferred_auth_method = "apikey"
  EOT

  additional_mcp_servers = <<-EOT
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

When no custom `base_config_toml` is provided, the module uses a minimal default with `preferred_auth_method = "apikey"`. For advanced options, see [Codex config docs](https://github.com/openai/codex/blob/main/codex-rs/config.md).

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
