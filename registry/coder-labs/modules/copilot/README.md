---
display_name: Copilot CLI
description: GitHub Copilot CLI agent for AI-powered terminal assistance
icon: ../../../../.icons/github.svg
verified: false
tags: [agent, copilot, ai, github, ai-gateway]
---

# Copilot

Install and configure the [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli) in your workspace for AI-powered coding assistance directly from the terminal.

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}
```

> [!WARNING]
> If upgrading from v0.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Copilot; you launch it yourself with a `coder_app` (see below). Keep using v0.x if you depend on the embedded web app or task reporting.

## Prerequisites

- **[Active Copilot subscription](https://docs.github.com/en/copilot/about-github-copilot/subscription-plans-for-github-copilot)** (GitHub Copilot Pro, Pro+, Business, or Enterprise)
- **`curl`** (or `wget`) available in the workspace for the official install script
- **GitHub authentication** via one of:
  - [Coder external authentication](https://coder.com/docs/admin/external-auth) (recommended), fetched at launch in your `coder_app`
  - Direct token via the `github_token` variable
  - Interactive login in Copilot (`/login`)

## Examples

### Launcher app with GitHub external auth

The module installs and configures Copilot. To run it, add a `coder_app` that
fetches a fresh GitHub token at launch and starts Copilot. This assumes you have
[Coder external authentication](https://coder.com/docs/admin/external-auth)
configured with `id = "github"`.

```tf
locals {
  copilot_workdir = "/home/coder/project"
}

module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = local.copilot_workdir
}

resource "coder_app" "copilot" {
  agent_id     = coder_agent.example.id
  slug         = "copilot"
  display_name = "Copilot"
  icon         = "/icon/github.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    token="$(coder external-auth access-token github)" && export GITHUB_TOKEN="$token" GH_TOKEN="$token"
    cd "${local.copilot_workdir}"
    exec copilot --allow-all-tools
  EOT
}
```

> [!NOTE]
> Tool permissions (`--allow-all-tools`, `--allow-tool`, `--deny-tool`) and
> session resumption (`--continue`) are session-only Copilot CLI flags, so pass
> them to `copilot` in your `coder_app` command rather than to the module.

### Direct token authentication

Provide a GitHub token instead of using Coder external auth. When set, the module
exports it to the workspace as `GITHUB_TOKEN` and `GH_TOKEN`.

```tf
variable "github_token" {
  type        = string
  description = "GitHub Personal Access Token"
  sensitive   = true
}

module "copilot" {
  source       = "registry.coder.com/coder-labs/copilot/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  workdir      = "/home/coder/project"
  github_token = var.github_token
}
```

> [!NOTE]
> OAuth tokens work best with Copilot. Personal Access Tokens may have limited functionality.

### Usage with AI Gateway

[AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) is a Premium Coder
feature that provides centralized LLM proxy management. When `enable_ai_gateway = true`,
the module points Copilot's [BYOK model provider](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models)
at Coder's AI Gateway using the workspace owner's session token.

```tf
module "copilot" {
  source            = "registry.coder.com/coder-labs/copilot/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  workdir           = "/home/coder/project"
  enable_ai_gateway = true
  copilot_model     = "gpt-5"
}
```

The module sets `COPILOT_PROVIDER_TYPE`, `COPILOT_PROVIDER_BASE_URL`, and
`COPILOT_PROVIDER_API_KEY` in the workspace environment. Set `copilot_model` to a
model id served by your AI Gateway provider.

> [!CAUTION]
> `enable_ai_gateway = true` is mutually exclusive with `github_token`. Setting both fails at plan time. AI Gateway authenticates the model provider with the Coder session token; GitHub authentication is only needed if your workflow calls GitHub tools.

> [!NOTE]
> Copilot CLI cannot send custom request headers and does not route inline completions through a gateway; only chat/agent/CLI model traffic is proxied.

### Advanced configuration

Customize MCP servers, trusted directories, and Copilot settings:

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  # Version pinning (defaults to "latest")
  copilot_version = "0.0.334"

  trusted_directories = ["/home/coder/project", "/tmp"]

  # Custom Copilot configuration (written to config.json)
  copilot_config = jsonencode({
    banner = "never"
    theme  = "dark"
  })

  # MCP server configuration (merged into ~/.copilot/mcp-config.json)
  mcp_config = jsonencode({
    mcpServers = {
      filesystem = {
        command = "npx"
        args    = ["-y", "@modelcontextprotocol/server-filesystem", "/home/coder/project"]
        type    = "local"
        tools   = ["*"]
      }
    }
  })

  # Pre-install an MCP server for faster startup
  pre_install_script = <<-EOT
    #!/bin/bash
    npm install -g @modelcontextprotocol/server-filesystem
  EOT
}
```

> [!NOTE]
> Servers from `mcp_config` are merged into `~/.copilot/mcp-config.json`, Copilot's documented user-level MCP config. GitHub Copilot CLI does not automatically install MCP servers. Either use `npx -y` in the config (shown above) to auto-install on each run, or pre-install MCP servers in `pre_install_script` for faster startup.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync`
names for the scripts this module creates (pre_install, install, post_install).
Scripts that were not configured are absent.

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"
}

resource "coder_script" "post_copilot" {
  agent_id     = coder_agent.example.id
  display_name = "Run after Copilot install"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    trap 'coder exp sync complete post-copilot' EXIT
    coder exp sync want post-copilot ${join(" ", module.copilot.scripts)}
    coder exp sync start post-copilot

    copilot --version
  EOT
}
```

## Authentication

The module supports multiple GitHub authentication methods:

1. **[Coder External Auth](https://coder.com/docs/admin/external-auth) (Recommended)** - Fetch a fresh token at launch in your `coder_app` command with `coder external-auth access-token <id>`.
2. **Direct Token** - Pass the `github_token` variable (OAuth or Personal Access Token). Exported as `GITHUB_TOKEN` and `GH_TOKEN`.
3. **Interactive** - Copilot prompts for login via the `/login` command if no auth is found.

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/copilot/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/copilot/logs/install.log
cat ~/.coder-modules/coder-labs/copilot/logs/pre_install.log
cat ~/.coder-modules/coder-labs/copilot/logs/post_install.log
```

## References

- [GitHub Copilot CLI Documentation](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli)
- [Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli)
- [Using your own LLM models (BYOK)](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models)
- [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway)
