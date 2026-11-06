---
display_name: Docker (Agent Relay)
description: Serve Agent Relay Claude Code and Cursor sessions from one template, one Docker container per session
icon: ../../../../.icons/docker.svg
verified: true
tags: [docker, container, agent, agent-relay, claude, cursor]
---

# Agent Relay on Docker Containers

A minimal template that serves [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
sessions for both Claude Code and Cursor. Agent Relay builds one workspace per
session, and the template runs it as a single Docker container. When the runner
exits, Agent Relay deletes the workspace.

## Prerequisites

- Coder 2.39.0 or newer, and Agent Relay v0.14.0 or newer, which the 1.0.0
  runner modules require. On an older deployment, pin
  `agent-relay-claude-code` to `0.4.0` and `agent-relay-cursor` to `0.7.0`;
  those releases receive the relay's credential as a build parameter instead
  of a workspace secret.
- A Docker host the provisioner can reach. The
  [Docker Containers](../docker/README.md) template covers giving Coder access
  to the Docker socket.
- The settings under [Template settings](#template-settings).

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

## Template settings

These are set on the template in Coder, not in Terraform:

- Turn on `allow_user_cancel_workspace_jobs`. Agent Relay cancels in-flight
  builds when it rebuilds or tears down a session's workspace, and degrades the
  pool without it.
- Give the Agent Relay service account `read` and `use` on the template, for
  example through the `use` role in the template's ACL.
- Do not put the template under a quota. Quota is enforced mid-build, so a
  build over quota fails, and each redelivery of the session fails the same
  way.
- Keep the autostop TTL finite, but longer than your longest session. Relay
  sessions do not count as workspace activity, so autostop can stop a
  workspace mid-session, and the TTL is the only limit on a worker that never
  receives a session.
- Turn on dormancy auto-deletion. Agent Relay never deletes a stopped
  workspace, and restarting one brings it back without a credential, where it
  idles. Delete stopped relay workspaces rather than starting them.

## Provisioners

Push the template with a provisioner tag, for example
`coder templates push <name> --provisioner-tag workload=agent-relay`, and run
dedicated provisioners with a matching key, so relay builds do not queue
behind human workspaces. Queue time counts against the start deadline: 300
seconds from the work order for Claude Code, and the pool's
`dispatch_deadline` for Cursor. With no matching provisioner, builds stay
`pending`.

## Prebuilt workspaces

The template keeps one prebuilt workspace per provider running, through a
`coder_workspace_preset` for each that pins only `self_hosted_provider`. Agent
Relay's builds match those presets, so a session claims a running workspace
rather than waiting for a new one to start. Prebuilt workspaces need a Premium
license; without one, no prebuilt workspaces are kept and every session starts
cold.

Each preset keeps one instance and replaces it after an hour unclaimed, so a
session does not start on a stale image or CLI. Size `instances` to how many
sessions start at once: every instance is a workspace that runs until a
session claims it, and once all are claimed, new sessions build cold until
Coder replaces them. Do not pin any other parameter in a preset, or Agent
Relay's builds stop matching it. If a pool sets more `template_parameters`,
pin the same values in its preset.

Prebuild jobs need provisioners too. Where possible, route them to dedicated
provisioners with the `is_prebuild` tag, as described in
[Prebuilt workspaces](https://coder.com/docs/admin/templates/extending-templates/prebuilt-workspaces),
so they do not compete with session builds.

The container is named and labeled by workspace ID only, unlike the
[Docker Containers](../docker/README.md) template, because Docker replaces a
container whose name, hostname or labels change, and a claim changes the
owner and workspace name.

## Workspace image

The default image, `ghcr.io/coder/agent-relay-workspace:latest`, carries both
CLIs, so neither module downloads one at start. It is a reference image,
rebuilt weekly; fork it and add your own tooling. With another image, each
module downloads its CLI when it is not on `PATH`, which counts against the
session's start deadline, so bake the CLIs in and set `install_cli = false`.

The image needs Claude Code v2.1.224 or newer and git 2.24 or newer. Anthropic
and Cursor reject an outdated CLI with an opaque error; rebuild the image when
that happens.

## Network

The Claude Code module runs every session with
`--permission-mode bypassPermissions`, because no terminal is attached to
answer a prompt. Apply default-deny egress to these workspaces and allow only
what sessions need. The minimum is:

- The Coder access URL, and any external DERP or STUN servers.
- The git host, such as `github.com`.
- Claude Code: `api.anthropic.com`, plus `claude.ai` and
  `downloads.claude.ai` when the CLI is installed at start.
- Cursor: `api2.cursor.sh`, `api2direct.cursor.sh`, `downloads.cursor.com` and
  `cloud-agent-artifacts.s3.us-east-1.amazonaws.com`, plus `cursor.com` when
  the CLI is installed at start.

Check [Anthropic's](https://code.claude.com/docs/en/self-hosted-environments-deploy#network-requirements)
and [Cursor's](https://cursor.com/docs/cloud-agent/self-hosted/pool) lists
before finalizing an allowlist. Keep workspace clocks synchronized: Anthropic
authentication fails when a clock is more than five minutes off.

## Logs

Each module writes its logs, including the runner's own, under
`$HOME/.coder-modules/coder/<module>/logs/`. Agent Relay deletes the workspace
when the runner exits, failures included, and the logs go with it. Ship them
to your own logging system to keep failure reasons.

## Source control

The template declares the `github` external auth provider as optional, so a
session can clone and push over HTTPS with the workspace owner's token, and
the [git-config](https://registry.coder.com/modules/coder/git-config) module
sets the commit identity. Change the external auth id to match your
deployment. Agent Relay builds workspaces without a person present, so the
link must be made ahead of time.

## Not included

- IDEs. Add modules such as
  [code-server](https://registry.coder.com/modules/coder/code-server) to look
  inside a session.
- Repository-scoped Cursor pools. The template must clone the pool's
  repository before the worker starts, and the worker must start in that
  checkout, which means setting `coder_agent.dir` to its path. This template
  does neither. A worker started outside the checkout registers as "Repo:
  (repo unavailable)", and Cursor can then create a second pool with the same
  name and no repository, where sessions land.
