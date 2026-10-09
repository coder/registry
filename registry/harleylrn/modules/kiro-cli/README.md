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
> If upgrading from v1.x.x of this module: v2 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Kiro CLI; launch it with your own `coder_app`. `workdir` is now optional. `trust_all_tools` is removed in favor of the `--trust-all-tools` flag in your launcher. `system_prompt` and the default agent template are removed: without `agent_config`, Kiro's built-in default agent is used. `kiro_install_url` now defaults to the official download host, and `auth_tarball` is no longer rendered into the install script. Keep using v1.x.x if you depend on Coder Tasks.

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

When `workdir` is set, the module creates it if missing. Pass `--model`, `--agent`, `--trust-all-tools`, `--trust-tools`, or any other [`kiro-cli chat` flag](https://kiro.dev/docs/reference/cli-commands/) in the launcher command.

> [!CAUTION]
> `--trust-all-tools` lets Kiro CLI run any tool, including shell commands, without asking for confirmation. Use it only in trusted environments, or prefer `--trust-tools` with a specific list.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for interactive `kiro-cli chat`, but one-shot commands like `kiro-cli chat --no-interactive` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### MCP servers and a custom agent

```tf
module "kiro_cli" {
  source       = "registry.coder.com/harleylrn/kiro-cli/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/project"
  auth_tarball = var.kiro_cli_auth_tarball

  mcp = jsonencode({
    mcpServers = {
      playwright = {
        command = "npx"
        args    = ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
      }
    }
  })

  agent_config = jsonencode({
    name           = "coder-agent"
    description    = "Coding agent for this workspace"
    prompt         = "You are a helpful coding assistant."
    tools          = ["read", "write", "shell"]
    allowedTools   = ["read"]
    includeMcpJson = true
  })
}
```

`mcp` is merged into the user-level `~/.kiro/settings/mcp.json`, so the servers apply to every Kiro CLI session in the workspace. Servers already in that file win on duplicate names, so edits made inside the workspace are never overwritten.

`agent_config` is written to `~/.kiro/agents/<name>.json` and set as `chat.defaultAgent` in `~/.kiro/settings/cli.json`; other settings are preserved. Custom agents only load servers from `mcp.json` when `includeMcpJson` is `true`. See the [agent configuration reference](https://kiro.dev/docs/custom-agents/configuration-reference/).

> [!NOTE]
> The Kiro CLI installer ships self-contained binaries and does not install Node.js. MCP servers whose `command` is `npx` or `uvx` need that runtime available in the workspace image, or installed with `pre_install_script`.

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

With the defaults, the module runs the [official installer](https://cli.kiro.dev/install), which installs the latest stable release and verifies its checksum. When `kiro_cli_version` or `kiro_install_url` is set, the module downloads `<kiro_install_url>/<kiro_cli_version>/kirocli-<arch>-linux.zip` (default host `https://prod.download.cli.kiro.dev/stable`) and runs the archive's `install.sh`. For a mirror, keep that layout and host both `kirocli-x86_64-linux.zip` and `kirocli-aarch64-linux.zip`. The archive path requires `unzip`.

The install is skipped when `kiro-cli` is already on `PATH` (and matches `kiro_cli_version` when pinned). If `install_kiro_cli = false`, a working `kiro-cli` must already be on `PATH`, or workspace startup fails.

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

Kiro CLI uses an active browser login first, then the `KIRO_API_KEY` environment variable. See [Kiro authentication](https://kiro.dev/docs/getting-started/authentication/).

- **Auth tarball**: log in on another machine and pass the resulting data directory as `auth_tarball`. It is exported as `KIRO_CLI_AUTH_TARBALL` and extracted to `~/.local/share/kiro-cli` at startup, replacing that directory. The workspace needs `zstd`.
- **API key**: set `api_key` to export `KIRO_API_KEY`. Kiro documents API keys for non-interactive (headless) use and requires a Pro or higher subscription.
- **Device flow**: without either, run `kiro-cli login` in the workspace terminal.

Neither secret is rendered into the install script. To generate the tarball:

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
