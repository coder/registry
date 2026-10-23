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

The gateway rejects requests whose `Host` is not in its allowlist (`Host header not allowed.`). At startup, the module derives the dashboard app's origin from the agent's `VSCODE_PROXY_URI`, which follows the deployment's wildcard access URL. It also derives an origin for each hostname in `workspace_proxy_hostnames`. The module passes these origins to the gateway in `KIROCREW_CORS_ORIGINS` and sets `dashboard.url` to the primary origin. The redirector sends your browser to the dashboard on the same hostname you opened the app from, primary or proxy, if that origin is in the allowlist. Otherwise, it sends your browser to the primary origin.

## Prerequisites

- Your Coder deployment must serve [wildcard subdomain apps](https://coder.com/docs/admin/setup#wildcard-access-url). Both apps are subdomain apps.
- The workspace image needs `bash`, `curl`, `openssl`, and `sha256sum`. The Kiro Crew installer provisions its own managed Python via `uv`, so no system Python is required. Use `pre_install_script` to install missing packages.
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
    sudo apt-get install -y curl openssl unzip
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

### Workspace proxies

Without configuration, a browser that opens Kiro Crew through a [workspace proxy](https://coder.com/docs/admin/networking/workspace-proxies) is redirected to the dashboard on the primary deployment's wildcard hostname. To keep dashboard traffic on the proxy, list each proxy's wildcard hostname, as shown in the `wildcard_hostname` field of `/api/v2/regions`:

```tf
module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  workspace_proxy_hostnames = [
    "*.apps.eu.example.com",
    "*.apps.us.example.com",
  ]
}
```

The gateway's allowlist is fixed when the workspace starts, so restart the workspace after you add a proxy.

### Custom dashboard origin

The module derives the dashboard origin from the agent's `VSCODE_PROXY_URI`. If that variable is not set, or you serve the dashboard from another origin, set the dashboard origin explicitly. The redirector uses it in place of the primary origin. The hidden app's slug is `<slug>-dashboard`.

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

## Session continuity

Kiro Crew is a long-running gateway, not a one-shot CLI. The `kirocrew gateway` process owns your sessions, chat transcripts, task state, and agent memory, so work continues across disconnects and restarts:

- **Reconnecting resumes where you left off.** Closing the dashboard tab or losing your connection does not end a session. Reopening the **Kiro Crew** app reattaches to the same running gateway and its in-progress sessions and transcripts.
- **Sessions survive workspace restarts.** All gateway state lives under `$HOME` (`~/.kiro`). On a persistent home directory it is preserved across stop/start and rebuilds; the module's start script relaunches the gateway automatically on the next start, and your prior sessions are still there.

Use a persistent home directory to retain sessions, transcripts, and Kiro credentials across restarts. For example, mount a persistent volume at `/home/coder`.

## Restricted and air-gapped environments

### Use an internal mirror for the installers

By default the module downloads the Kiro CLI and Kiro Crew installers from the public Kiro endpoints. Point `kiro_cli_install_url` and `kirocrew_install_url` at an internal mirror or artifact store so the workspace never reaches the public internet for them:

```tf
module "kiro-crew" {
  source   = "registry.coder.com/coder-labs/kiro-crew/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  kiro_cli_install_url = "https://artifacts.example.com/kiro/cli-install.sh"
  kirocrew_install_url = "https://artifacts.example.com/kiro/crew-cli.sh"
}
```

### Bring your own binaries (skip all downloads)

`use_cached` defaults to `true`, which skips both installers when `kiro-cli` and `kirocrew` are already present (on `PATH` or in the managed venv at `~/.kiro/crew-venv`). Bake the binaries into your workspace image to run fully offline with no installer downloads at all:

```Dockerfile
# In your workspace image
RUN curl -fsSL https://cli.kiro.dev/install | bash \
  && curl -fsSL https://download.crew.kiro.dev/cli.sh | sh
```

```tf
module "kiro-crew" {
  source     = "registry.coder.com/coder-labs/kiro-crew/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  use_cached = true # default; skips the installers when the binaries already exist
}
```

With the binaries baked in, neither installer endpoint is contacted.

### Network access

The module and the tools it runs contact these external endpoints. Nothing else is required by the module itself.

| Phase              | Endpoint                                  | Purpose                                                           | Avoid by                                                          |
| ------------------ | ----------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| Install            | `cli.kiro.dev`                            | Kiro CLI installer script                                         | Set `kiro_cli_install_url`, or bake in the binary                 |
| Install            | `download.crew.kiro.dev`                  | Kiro Crew installer script                                        | Set `kirocrew_install_url`, or bake in the binary                 |
| Install            | Astral (`uv` and managed CPython)         | The Kiro Crew installer uses `uv` to provision its managed Python | Bake `~/.kiro/crew-python` and `~/.kiro/crew-venv` into the image |
| Install            | `pypi.org`, `files.pythonhosted.org`      | The Kiro Crew Python dependencies                                 | Mirror PyPI, or bake in the `~/.kiro/crew-venv`                   |
| Install (optional) | Ubuntu package mirrors                    | Only if your `pre_install_script` installs packages               | Pre-install the packages in the image                             |
| Runtime            | Kiro service and model/embeddings backend | Kiro CLI sign-in and agent model/embeddings calls                 | Required for agents to call models; not overridable               |

For a fully air-gapped deployment: bake in the binaries and the managed venv, mirror PyPI, and confirm the workspace can still reach the Kiro model backend — agents cannot call models without it.

## Troubleshooting

Logs are written to `$HOME/.coder-modules/coder-labs/kiro-crew/logs/`:

- `install.log` and `start.log` for the module scripts.
- `gateway.log` for the `kirocrew gateway` process.
- `redirector.log` for the token-minting redirector.

The start script launches the gateway in a detached session and returns immediately, because a slow cold start could otherwise exceed the agent's script timeout. Readiness is reported by the app healthchecks, so the app can show as unhealthy for a short time after the workspace starts. While the gateway is starting, the Kiro Crew app responds with `503`; retry after a few seconds.

- **`Host header not allowed.`:** the browser's origin is not in the gateway's allowlist. `start.log` lists the allowed origins. If you opened the dashboard through a workspace proxy, add its wildcard hostname to `workspace_proxy_hostnames`. Otherwise, set `dashboard_origin` or `allowed_origins` to the origin shown in the browser.
- **`ImportError: No module named 'aiohttp'` on gateway start:** the managed venv at `~/.kiro/crew-venv` was built with a foreign `PYTHONPATH`. The install script unsets `PYTHONPATH` and `PYTHONHOME`; remove `~/.kiro/crew-venv`, set `use_cached = false`, and restart the workspace.
- **Sandbox warnings:** Kiro Crew sandboxes agent subprocesses with a Linux user namespace. When the workspace cannot create one, which is common in Kubernetes pods, the gateway is configured with `agent.sandbox_allow_unsandboxed_exec` and the workspace is the isolation boundary.
- **Expected warnings:** `Vendored llama-cpp-python failed to import` (the gateway falls back to API-based embeddings) and `cgroup v2 scope enforcement unavailable` (no systemd user session in containers) do not affect the gateway.
