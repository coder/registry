---
display_name: Goose
description: Install and configure the Goose AI agent in your workspace.
icon: ../../../../.icons/goose.svg
verified: true
tags: [agent, goose, ai]
---

# Goose

Install and configure the [Goose](https://goose-docs.ai/) agent in your workspace.

```tf
module "goose" {
  source         = "registry.coder.com/coder/goose/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
}
```

> [!WARNING]
> If upgrading from v3.x.x of this module: v4 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Goose; launch it with your own `coder_app`. `order`, `group`, `subdomain`, `install_agentapi`, `agentapi_version`, the `task_app_id` output, the `GOOSE_TASK_PROMPT` and `GOOSE_SYSTEM_PROMPT` environment variables, and the built-in `coder` extension are removed, and `folder` is renamed to `workdir`. `goose_provider` and `goose_model` are now exported as `GOOSE_PROVIDER` and `GOOSE_MODEL` instead of being written to `config.yaml`, and `config.yaml` is no longer overwritten. Keep using v3.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  goose_workdir = "/home/coder/project"
}

module "goose" {
  source         = "registry.coder.com/coder/goose/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  workdir        = local.goose_workdir
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
}

resource "coder_env" "anthropic_api_key" {
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_app" "goose" {
  agent_id     = coder_agent.main.id
  slug         = "goose"
  display_name = "Goose"
  icon         = "/icon/goose.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.goose_workdir}"
    exec goose session
  EOT
}
```

Goose reads provider credentials from environment variables such as `ANTHROPIC_API_KEY`. See [Goose providers](https://goose-docs.ai/docs/getting-started/providers) and [CLI commands](https://goose-docs.ai/docs/guides/goose-cli-commands) for launcher options.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for an interactive `goose session`, but one-shot commands like `goose run` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### Extensions (MCP)

```tf
module "goose" {
  source         = "registry.coder.com/coder/goose/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"

  additional_extensions = <<-EOT
    playwright:
      name: playwright
      type: stdio
      cmd: npx
      args: ["-y", "@playwright/mcp@latest", "--headless", "--isolated"]
      enabled: true
      timeout: 300
  EOT
}
```

`additional_extensions` uses the [`extensions`](https://goose-docs.ai/docs/guides/config-files#extensions-configuration) format of `config.yaml`. Extensions that already exist in `config.yaml` are kept.

### Pinned version

```tf
module "goose" {
  source         = "registry.coder.com/coder/goose/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  goose_version  = "v1.54.0"
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
}
```

See [Goose releases](https://github.com/aaif-goose/goose/releases) for available versions.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "goose" {
  source         = "registry.coder.com/coder/goose/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
}

resource "coder_script" "post_goose" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Goose install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-goose' EXIT
    coder exp sync want post-goose ${join(" ", module.goose.scripts)}
    coder exp sync start post-goose

    goose --version
  EOT
}
```

## Troubleshooting

Check the log files in `~/.coder-modules/coder/goose/logs/` for detailed information, and run `goose info -v` to see the configuration Goose loads.

```bash
cat ~/.coder-modules/coder/goose/logs/install.log
cat ~/.coder-modules/coder/goose/logs/pre_install.log
cat ~/.coder-modules/coder/goose/logs/post_install.log
```

## References

- [Goose documentation](https://goose-docs.ai/docs/)
- [Goose configuration files](https://goose-docs.ai/docs/guides/config-files)
- [Goose environment variables](https://goose-docs.ai/docs/guides/environment-variables)
- [Using extensions](https://goose-docs.ai/docs/getting-started/using-extensions)
