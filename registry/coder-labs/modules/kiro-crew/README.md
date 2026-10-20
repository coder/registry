---
display_name: Kiro Crew
description: Run the Kiro Crew gateway in your workspace and open its web dashboard from a self-authenticating Coder app.
icon: ../../../../.icons/kiro.svg
verified: false
tags: [agent, ai, kiro, aws, mcp]
---

# Kiro Crew

Install [Kiro CLI](https://kiro.dev/cli/) and [Kiro Crew](https://github.com/kirodotdev/KiroCrew), run the `kirocrew gateway` in the workspace, and open the Kiro Crew web dashboard from a Coder app.

```tf
module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

The module adds two subdomain apps:

- A visible **Kiro Crew** app that points at a loopback redirector. Each time you open it, the redirector mints a short-lived gateway token and redirects your browser to the dashboard with that token, so you land on an authenticated dashboard without running `kirocrew token`.
- A hidden `<slug>-dashboard` app that serves the dashboard and its websocket through Coder's subdomain proxy.

The gateway rejects requests whose `Host` is not loopback (`Host header not allowed.`). The module derives the dashboard app's origin from the Coder access URL, passes it to the gateway in `KIROCREW_CORS_ORIGINS`, and sets `dashboard.url` so token cookies are scoped to it.

## Prerequisites

- Your Coder deployment must serve [wildcard subdomain apps](https://coder.com/docs/admin/setup#wildcard-access-url). Both apps are subdomain apps.
- The workspace image needs `bash`, `curl`, `python3` with the `venv` module, `openssl`, and `sha256sum`. The Kiro Crew installer uses Python 3.10 or newer and prefers 3.12 or 3.11. Use `pre_install_script` to install missing packages.
- The Coder agent must support `coder exp sync`, which orders the install and start scripts.
- A Kiro account. See [Authentication](#authentication).

## Examples

### Install system prerequisites first

```tf
module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  pre_install_script = <<-EOT
    #!/usr/bin/env bash
    sudo apt-get update -qq
    sudo apt-get install -y curl openssl python3-venv
  EOT
}
```

### Add MCP servers

`extra_mcp_json` is deep-merged into `~/.kiro/settings/mcp.json`. Keys you set replace existing keys with the same name; other existing servers are kept.

```tf
module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  extra_mcp_json = jsonencode({
    mcpServers = {
      fetch = {
        command = "uvx"
        args    = ["mcp-server-fetch"]
      }
    }
  })
}
```

### Custom wildcard domain

If your deployment's wildcard access URL uses a different host than its access URL, set the dashboard origin explicitly. The hidden app's slug is `<slug>-dashboard`.

```tf
module "kiro-crew" {
  source           = "registry.coder.com/coder-labs/kiro-crew/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  dashboard_origin = "https://kirocrew-dashboard--${data.coder_workspace.me.name}--${data.coder_workspace_owner.me.name}.apps.example.com"
}
```

Use `allowed_origins` to trust additional origins, such as the Coder access URL, in the gateway's allowlist.

### AWS Builder ID token from external auth

```tf
data "coder_external_auth" "aws_builder_id" {
  id = "aws-builder-id"
}

module "kiro-crew" {
  source               = "registry.coder.com/coder-labs/kiro-crew/coder"
  version              = "1.0.0"
  agent_id             = coder_agent.main.id
  aws_builder_id_token = data.coder_external_auth.aws_builder_id.access_token
}
```

The token is exported to the workspace as `KIRO_AWS_BUILDER_ID_TOKEN` and is not rendered into any script.

## Authentication

The gateway starts with the workspace, but agents cannot call models until Kiro CLI is authenticated. Kiro credentials are stored under `$HOME`, so use a persistent home directory to keep them across restarts.

- **Headless:** create a Coder user secret that sets `KIRO_API_KEY` before you start the workspace, for example `coder secret create kiro-api-key --env KIRO_API_KEY`. The gateway inherits it, and Kiro CLI authenticates without a browser. Generating API keys requires a Kiro subscription that supports them.
- **Interactive:** open a terminal, run `kiro-cli login`, and complete the device-code sign-in with AWS Builder ID or IAM Identity Center. Check the result with `kiro-cli whoami`.

## Troubleshooting

Logs are written to `$HOME/.coder-modules/coder-labs/kiro-crew/logs/`:

- `install.log` and `start.log` for the module scripts.
- `gateway.log` for the `kirocrew gateway` process.
- `redirector.log` for the token-minting redirector.

The start script launches the gateway in a detached session and returns immediately, because a slow cold start could otherwise exceed the agent's script timeout. Readiness is reported by the app healthchecks, so the app can show as unhealthy for a short time after the workspace starts. While the gateway is starting, the Kiro Crew app responds with `503`; retry after a few seconds.

- **`Host header not allowed.`:** the browser's origin is not in the gateway's allowlist. Set `dashboard_origin` or `allowed_origins` to the origin shown in the browser.
- **`ImportError: No module named 'aiohttp'` on gateway start:** the managed venv at `~/.kiro/crew-venv` was built with a foreign `PYTHONPATH`. The install script unsets `PYTHONPATH` and `PYTHONHOME`; remove `~/.kiro/crew-venv`, set `use_cached = false`, and restart the workspace.
- **Kiro Crew installer fails in `pipx` with `JSONDecodeError`:** distro `pipx` on Python 3.13 or newer crashes. The install script builds its own `pipx` with `python3.12` or `python3.11` when available, so install one of them, or use an image based on Ubuntu 24.04.
- **Sandbox warnings:** Kiro Crew sandboxes agent subprocesses with a Linux user namespace. When the workspace cannot create one, which is common in Kubernetes pods, the gateway is configured with `agent.sandbox_allow_unsandboxed_exec` and the workspace is the isolation boundary.
- **Expected warnings:** `Vendored llama-cpp-python failed to import` (the gateway falls back to API-based embeddings) and `cgroup v2 scope enforcement unavailable` (no systemd user session in containers) do not affect the gateway.
