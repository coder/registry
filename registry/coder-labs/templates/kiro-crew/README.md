---
display_name: Kiro Crew on Kubernetes
description: Kubernetes workspaces that run the Kiro Crew gateway and web dashboard, with Kiro CLI, code-server, and a persistent home volume.
icon: ../../../../.icons/kiro.svg
verified: false
tags: [kubernetes, container, kiro, ai, agent, mcp]
---

# Kiro Crew on Kubernetes

Provision Kubernetes pods as [Coder workspaces](https://coder.com/docs/workspaces) that run [Kiro Crew](https://github.com/kirodotdev/KiroCrew). Kiro Crew is a persistent development workspace built on Kiro CLI: a long-running gateway owns memory, transcripts, and artifacts, and a web dashboard lets you chat with agents, run multi-step tasks, schedule jobs, and extend agents with skills and MCP servers.

The template uses the [kiro-crew](../../modules/kiro-crew/README.md) module to install Kiro CLI and Kiro Crew, start the gateway, and publish the dashboard through Coder's authenticated subdomain proxy. The **Kiro Crew** app opens an authenticated dashboard without a separate token step.

Each workspace also includes:

- A **Kiro CLI** terminal app for interactive sign-in.
- code-server and the Kiro IDE app.
- The Coder MCP server in `~/.kiro/settings/mcp.json`, so agents can work with Coder workspaces and templates.
- An optional repository clone on start.
- A persistent volume at `/home/coder` that keeps installs, Kiro credentials, and Kiro Crew state across restarts.
- CPU, memory, and disk usage on the workspace page.

## Prerequisites

### Infrastructure

- A Kubernetes cluster that Coder can provision into. The namespace must exist before you create workspaces. If the Coder host runs outside the cluster, set `use_kubeconfig = true` and provide `~/.kube/config` on the Coder host.
- A storage class that can provision `ReadWriteOnce` persistent volumes.
- [Wildcard subdomain apps](https://coder.com/docs/admin/setup#wildcard-access-url). The dashboard is a subdomain app, and the dashboard app tile does not resolve without a wildcard access URL.
- Outbound access from workspace pods to the Ubuntu package mirrors, the Kiro download hosts (`cli.kiro.dev`, `download.crew.kiro.dev`), and the hosts the bundled Kiro Crew installer uses to provision its managed Python (`uv`/Astral and PyPI).

The default image pins `codercom/enterprise-base` to a known-good Ubuntu 24.04 build. The Kiro Crew installer provisions its own managed Python via `uv`, so the image does not need a specific system Python.

### Kiro account

Agents cannot call models until Kiro CLI is authenticated. Kiro credentials are stored in the persistent home volume, so you only sign in once per workspace.

- **Headless:** before you start the workspace, create a Coder user secret that sets `KIRO_API_KEY`:

  ```sh
  coder secret create kiro-api-key --description "Kiro CLI headless auth" --env KIRO_API_KEY
  ```

  The gateway inherits the variable and Kiro CLI authenticates without a browser. Generating API keys requires a Kiro subscription that supports them; on enterprise-managed accounts an administrator must enable it. Rotating or deleting the Coder secret does not revoke the key in Kiro.

- **Interactive:** open the **Kiro CLI** app, run `kiro-cli login`, and complete the device-code sign-in with AWS Builder ID or IAM Identity Center. Check the result with `kiro-cli whoami`.

If agents need AWS credentials, set `service_account_name` to a service account that is mapped to an IAM role, or run `aws configure` in the workspace.

## Use the dashboard

1. Authenticate Kiro CLI as described above.
1. Open the **Kiro Crew** app. The gateway starts in the background, so the app can report `503` or show as unhealthy for a short time after the workspace starts.
1. Start a session. If model calls fail with an authentication error, complete Kiro sign-in and retry.

Gateway, redirector, and script logs are in `~/.coder-modules/coder-labs/kiro-crew/logs/`.

## Notes

- Kiro Crew sandboxes agent subprocesses with Linux user namespaces. Many Kubernetes nodes disable them (`user.max_user_namespaces=0`); in that case the module allows unsandboxed execution and the pod is the isolation boundary.
- The Coder MCP configuration stores your Coder session token in `~/.kiro/settings/mcp.json` on the workspace volume. Remove the `coder` entry from that file if you do not want agents to act on your behalf in Coder.
