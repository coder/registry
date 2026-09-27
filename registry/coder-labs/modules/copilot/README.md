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
> If upgrading from v0.x of this module: v1 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Copilot; you launch it yourself with a `coder_app` (see below).

## Examples

### Launcher app with GitHub external auth

The module installs and configures Copilot. Use the
[`coder_external_auth`](https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/external_auth)
data source to fetch a GitHub token and pass it to the module, then add a
`coder_app` to launch Copilot. This assumes you have
[Coder external authentication](https://coder.com/docs/admin/external-auth)
configured with `id = "github"`.

```tf
locals {
  copilot_workdir = "/home/coder/project"
}

data "coder_external_auth" "github" {
  id = "github"
}

module "copilot" {
  source       = "registry.coder.com/coder-labs/copilot/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  workdir      = local.copilot_workdir
  github_token = data.coder_external_auth.github.access_token
}

resource "coder_app" "copilot" {
  agent_id     = coder_agent.example.id
  slug         = "copilot"
  display_name = "Copilot"
  icon         = "/icon/github.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.copilot_workdir}"
    exec copilot --allow-all-tools
  EOT
}
```

### Direct token authentication

Provide a GitHub token instead of using Coder external auth. When set, the module
exports it to the workspace as `COPILOT_GITHUB_TOKEN`.

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

### Usage with AI Gateway Proxy

[AI Gateway Proxy](https://coder.com/docs/ai-coder/ai-gateway/ai-gateway-proxy) routes Copilot traffic through [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) for centralized LLM management and governance.

```tf
module "aibridge-proxy" {
  source    = "registry.coder.com/coder/aibridge-proxy/coder"
  version   = "1.0.1"
  agent_id  = coder_agent.main.id
  proxy_url = "https://aiproxy.example.com"
}

module "copilot" {
  source               = "registry.coder.com/coder-labs/copilot/coder"
  version              = "1.0.0"
  agent_id             = coder_agent.main.id
  workdir              = "/home/coder/project"
  enable_ai_gateway    = true
  ai_gateway_auth_url  = module.aibridge-proxy.proxy_auth_url
  ai_gateway_cert_path = module.aibridge-proxy.cert_path
}
```

When `enable_ai_gateway = true`, the module sets `HTTPS_PROXY` and `NODE_EXTRA_CA_CERTS` as workspace environment variables so Copilot routes through the proxy.

> [!NOTE]
> AI Gateway Proxy is a Premium Coder feature that requires the [AI Governance Add-On](https://coder.com/docs/ai-coder/ai-governance). See the [setup guide](https://coder.com/docs/ai-coder/ai-gateway/ai-gateway-proxy/setup) for configuring the proxy on your deployment. GitHub authentication is still required; the proxy does not replace it.

> [!IMPORTANT]
> Unlike the pre-`v1` module (which scoped the proxy to the Copilot process via its start script), these variables are set at the agent level and therefore apply workspace-wide. Ensure the `aibridge-proxy` module completes before Copilot is launched so the CA certificate exists. For strict process-scoping, set `HTTPS_PROXY`/`NODE_EXTRA_CA_CERTS` in your own launcher `coder_app` instead.

### Advanced configuration

Customize MCP servers, policy, and Copilot settings:

```tf
module "copilot" {
  source   = "registry.coder.com/coder-labs/copilot/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  workdir  = "/home/coder/project"

  # Version pinning (defaults to "latest")
  copilot_version = "0.0.334"

  # Policy written to /etc/github-copilot/managed-settings.json (highest precedence).
  # Only supported keys apply (model, permissions, allowedMcpServers, telemetry, sandbox, ...).
  managed_settings = {
    model = "claude-sonnet-4.5"
    permissions = {
      deny = ["Shell(rm -rf *)"]
    }
  }

  # MCP server configuration (merged into ~/.copilot/mcp-config.json)
  mcp = jsonencode({
    mcpServers = {
      playwright = {
        command = "npx"
        args    = ["-y", "@playwright/mcp@latest"]
        type    = "local"
        tools   = ["*"]
      }
    }
  })

  # Pre-install an MCP server for faster startup
  pre_install_script = <<-EOT
    #!/usr/bin/env bash
    npm install -g @playwright/mcp
  EOT
}
```

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
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-copilot' EXIT
    coder exp sync want post-copilot ${join(" ", module.copilot.scripts)}
    coder exp sync start post-copilot

    copilot --version
  EOT
}
```

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
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
