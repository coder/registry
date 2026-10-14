---
display_name: Kiro CLI
description: Install and configure Kiro CLI in your workspace.
icon: ../../../../.icons/kiro.svg
verified: true
tags: [agent, ai, kiro, kiro-cli]
---

# Kiro CLI

Install and configure [Kiro CLI](https://kiro.dev/docs/cli/) in your workspace.

```tf
module "kiro_cli" {
  source   = "registry.coder.com/harleylrn/kiro-cli/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}
```

> [!WARNING]
> If upgrading from v1.x.x of this module: v2 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Kiro CLI; launch it with your own `coder_app`. `ai_prompt`, `system_prompt`, and `trust_all_tools` are removed in favor of `kiro-cli chat` flags in your launcher, and without `agent_config` Kiro's built-in default agent is used. Keep using v1.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  kiro_workdir = "/home/coder/project"
}

module "kiro_cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.main.id
  workdir      = local.kiro_workdir
  auth_tarball = var.kiro_cli_auth_tarball
}

resource "coder_app" "kiro_cli" {
  agent_id     = coder_agent.main.id
  slug         = "kiro-cli"
  display_name = "Kiro CLI"
  icon         = "/icon/kiro.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.kiro_workdir}"
    exec kiro-cli chat --trust-all-tools
  EOT
}
```

See [`kiro-cli chat` flags](https://kiro.dev/docs/reference/cli-commands/) for launcher options such as `--agent`, `--model`, and `--trust-tools`.

> [!CAUTION]
> `--trust-all-tools` lets Kiro CLI run any tool, including shell commands, without asking for confirmation. Use it only in trusted environments, or prefer `--trust-tools` with a specific list.

### Custom agent

```tf
module "kiro_cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/project"
  auth_tarball = var.kiro_cli_auth_tarball

  agent_config = jsonencode({
    name         = "coder-agent"
    description  = "Coding agent for this workspace"
    prompt       = "You are a helpful coding assistant."
    tools        = ["read", "write", "shell"]
    allowedTools = ["read"]
    mcpServers = {
      playwright = {
        command = "npx"
        args    = ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
      }
    }
  })
}
```

`agent_config` uses the [agent configuration](https://kiro.dev/docs/custom-agents/configuration-reference/) format and is set as `chat.defaultAgent`.

### Pinned version or internal mirror

```tf
module "kiro_cli" {
  source           = "registry.coder.com/harleylrn/kiro-cli/coder"
  version          = "2.0.0"
  agent_id         = coder_agent.main.id
  kiro_cli_version = "2.26.0"
  kiro_install_url = "https://artifacts.internal.corp/kiro-cli-releases"
}
```

With the defaults, the module runs the official installer. Otherwise it installs `<kiro_install_url>/<kiro_cli_version>/kirocli-<arch>-linux.zip`. See [Kiro CLI installation](https://kiro.dev/docs/getting-started/installation/).

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "kiro_cli" {
  source   = "registry.coder.com/harleylrn/kiro-cli/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "post_kiro_cli" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Kiro CLI install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-kiro-cli' EXIT
    coder exp sync want post-kiro-cli ${join(" ", module.kiro_cli.scripts)}
    coder exp sync start post-kiro-cli

    kiro-cli --version
  EOT
}
```

## Authentication

Set `api_key` (exported as `KIRO_API_KEY`), pass a pre-authenticated `auth_tarball` (requires `zstd`), or run `kiro-cli login` in the workspace. See [Kiro authentication](https://kiro.dev/docs/getting-started/authentication/).

To generate the tarball:

```bash
#!/usr/bin/env bash
kiro-cli login
cd ~/.local/share/kiro-cli
tar -c . | zstd | base64 -w 0
```

> [!IMPORTANT]
> The tarball contains authentication credentials. Store it as a sensitive variable, give each user their own, and regenerate it after logging out or re-authenticating.

## Troubleshooting

Check the log files in `~/.coder-modules/harleylrn/kiro-cli/logs/` for detailed information, and run `kiro-cli doctor` in the workspace.

```bash
cat ~/.coder-modules/harleylrn/kiro-cli/logs/install.log
cat ~/.coder-modules/harleylrn/kiro-cli/logs/pre_install.log
cat ~/.coder-modules/harleylrn/kiro-cli/logs/post_install.log
```

## References

- [Kiro CLI documentation](https://kiro.dev/docs/cli/)
- [Kiro CLI commands](https://kiro.dev/docs/reference/cli-commands/)
- [Kiro MCP configuration](https://kiro.dev/docs/mcp/configuration/)
- [Kiro settings reference](https://kiro.dev/docs/reference/settings/)
