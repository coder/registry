---
display_name: Kubernetes (Agent Relay)
description: Serve Agent Relay Claude Code and Cursor sessions from one template, one Kubernetes Pod per session
icon: ../../../../.icons/kubernetes.svg
verified: true
tags: [kubernetes, container, agent, agent-relay, claude, cursor]
---

# Agent Relay on Kubernetes Pods

A minimal template that serves [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
sessions for both Claude Code and Cursor. Agent Relay builds one workspace per
session, and the template runs it as a single Kubernetes Pod. When the runner
exits, Agent Relay deletes the workspace.

## Prerequisites

- Coder 2.39.0 or newer, and Agent Relay v0.14.0 or newer.
- A Kubernetes cluster and an existing namespace for workspace Pods. The
  provider authenticates through `~/.kube/config` on the Coder host, or through
  the provisioner's in-cluster ServiceAccount.
- The template setting that lets users cancel workspace jobs must be on, and
  the Agent Relay service account needs the `use` role on the template.

## Selecting the provider

The `self_hosted_provider` parameter decides which runner module a build
instantiates: [agent-relay-claude-code](https://registry.coder.com/modules/coder/agent-relay-claude-code)
or [agent-relay-cursor](https://registry.coder.com/modules/coder/agent-relay-cursor).
Each Agent Relay pool sets it through `template_parameters`, so a Claude Code
pool and a Cursor pool can share this template:

```json
{ "template_parameters": { "self_hosted_provider": "cursor" } }
```

The `agent_relay_status` metadata item on the agent is required. Agent Relay
reads it to decide when to delete the workspace, so do not rename its key.

## Workspace image

The default image, `ghcr.io/coder/agent-relay-workspace:latest`, carries both
CLIs, so neither module downloads one at start. With another image, each
module downloads its CLI when it is not on `PATH`, which counts against the
session's start deadline.

## Source control

The template declares the `github` external auth provider as optional, so a
session can clone and push over HTTPS with the workspace owner's token, and
the [git-config](https://registry.coder.com/modules/coder/git-config) module
sets the commit identity. Change the external auth id to match your
deployment. Agent Relay builds workspaces without a person present, so the
link must be made ahead of time.

## Not included

- Prebuilt workspaces. A Claude Code session must start within 300 seconds of
  its work order. To start faster, add a `coder_workspace_preset` for each
  provider that sets only `self_hosted_provider`, with a `prebuilds` block.
- IDEs. Add modules such as
  [code-server](https://registry.coder.com/modules/coder/code-server) to look
  inside a session.
- Repository-scoped Cursor pools. The template must clone the pool's
  repository before the worker starts, and this template does not.
