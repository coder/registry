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

- Coder 2.39.0 or newer, and Agent Relay v0.14.0 or newer, which the 1.x
  runner modules require. On older versions, pin `agent-relay-claude-code` to
  `0.4.0` and `agent-relay-cursor` to `0.7.0`.
- A Kubernetes cluster and an existing namespace for workspace Pods. The
  provider authenticates through `~/.kube/config` on the Coder host, or through
  the provisioner's in-cluster ServiceAccount.
- An Agent Relay deployment. [Set up Agent Relay](https://coder.com/docs/ai-coder/agent-relay/setup)
  covers the service account, provisioners, pools, and the template settings
  every relay template needs, such as `allow_user_cancel_workspace_jobs`.

## Architecture

This template provisions the following resources:

- Kubernetes Pod (ephemeral), one per session, named by workspace ID, with
  `cpu` and `memory` as both its requests and limits
- Two `coder_workspace_preset` blocks, one per provider, keeping
  `claude_code_prebuilds` and `cursor_prebuilds` prebuilt workspaces running
- A `Workspace setup` script that clones a repository-scoped Cursor pool's
  repository, and does nothing on any other build
- A `coder_script_order` rule that starts the runner only after setup

There is no persistent volume. Agent Relay deletes the workspace when the
runner exits, so nothing in the Pod outlives its session. To pre-bake tools
into sessions, modify the container image.

## Selecting the provider

The `self_hosted_provider` parameter decides which runner module a build
instantiates: [agent-relay-claude-code](https://registry.coder.com/modules/coder/agent-relay-claude-code)
or [agent-relay-cursor](https://registry.coder.com/modules/coder/agent-relay-cursor).
Each Agent Relay pool sets it through `template_parameters`, so a Claude Code
pool and a Cursor pool can share this template:

```json
{ "template_parameters": { "self_hosted_provider": "cursor" } }
```

The parameter defaults to `claude`. A Cursor pool that leaves it out is marked
degraded, because a Claude Code build lacks the parameters Agent Relay stamps
for Cursor.

The agent publishes the modules' `agent_relay_status` and
`agent_relay_session_attached` metadata items. Agent Relay deletes the
workspace based on the first, so do not rename its key, and extends autostop
while the second reports an attached session.

## Startup order

A [`coder_script_order`](https://coder.com/docs/admin/templates/extending-templates/script-ordering)
rule starts the runner only after the
[git-config](https://registry.coder.com/modules/coder/git-config) module and
the `Workspace setup` script. Add any further setup that sessions depend on to
the rule's `after` list, as a `coder_script` resource or a module;
`coder_agent.startup_script` cannot be ordered.

If a setup step fails, Coder skips the runner and Agent Relay fails the
session, about a minute later on Agent Relay v0.16.0 or newer. Set
`requires = "completion"` on the rule to start the runner anyway.

## Repository-scoped Cursor pools

A Cursor pool scoped to one repository needs the repository cloned and the
worker started inside the checkout, or the worker registers as "Repo: (repo
unavailable)". The template does both when its `repo_url` parameter is set:
the setup script clones the URL into `/home/coder/repo`, and the worker starts
there. The Cursor module's own copy of the URL cannot be read by a template, so
set the URL twice in the pool:

```yaml
pools:
  cursor:
    - name: app
      cursor_pool_name: app
      repo_url: https://github.com/example/app
      template_parameters:
        self_hosted_provider: cursor
        repo_url: https://github.com/example/app
```

Leave `repo_url` out for any other pool. Claude Code builds ignore it, because
the Claude Code runner clones each session's repository itself.

## Prebuilt workspaces

Each provider has a `coder_workspace_preset` that keeps prebuilt workspaces
running and replaces each after an hour unclaimed, so a session claims a
running workspace instead of waiting for a cold start. Prebuilds need a
Premium license.

- Set `claude_code_prebuilds` and `cursor_prebuilds` (default `1` each) to how
  many sessions of that provider start at once. Each instance runs until a
  session claims it. Set `0` for a provider no pool uses.
- Pin only `self_hosted_provider` and any other values the pool sets in
  `template_parameters`, or Agent Relay's builds never match the preset.
  `repo_url` does not need pinning, because the clone runs on claim.
- A pool that pins `template_version` always builds cold, because prebuilds
  exist only for the active version.

See [Prebuilt workspaces](https://coder.com/docs/admin/templates/extending-templates/prebuilt-workspaces)
for routing prebuild jobs to their own provisioners.

## Workspace image

The default image, `ghcr.io/coder/agent-relay-workspace:latest`, is a
reference image that carries both CLIs, rebuilt weekly. Fork it and add your
own tooling. With another image, each module downloads its CLI at start when
it is not on `PATH`, which counts against the start deadline; bake the CLIs in
and set `install_cli = false` instead.

The Pod runs as uid 1000, the default image's `coder` user. A replacement
image needs a uid 1000 user that owns its home directory, or a matching change
to the Pod's `security_context`.

## Source control

The template declares the `github` external auth provider as optional, so a
session can clone and push over HTTPS with the workspace owner's token, and
the git-config module sets the commit identity. Change the external auth id to
match your deployment: Coder refuses to import the template if no external
auth provider has this id, even though it is optional. Agent Relay builds
workspaces without a person present, so owners must link their account ahead
of time.

## Security

The Claude Code module runs every session with
`--permission-mode bypassPermissions`, because no terminal is attached to
answer a prompt. Restrict workspace egress to the hosts listed for
[Claude Code](https://coder.com/docs/ai-coder/agent-relay/claude-code#network-requirements)
and [Cursor](https://coder.com/docs/ai-coder/agent-relay/cursor#network-requirements),
plus the internal services sessions need.

## Not included

- IDEs. Add modules such as
  [code-server](https://registry.coder.com/modules/coder/code-server) to look
  inside a session.

For failures, see [Troubleshoot Agent Relay](https://coder.com/docs/ai-coder/agent-relay/troubleshooting).
