---
display_name: Coder CLI Workspace
description: A pre-authenticated Coder CLI workspace for operating a Coder deployment from the agent
icon: ../../../../.icons/coder.svg
verified: false
tags: [docker, container, cli, admin, agent]
---

# Coder CLI Workspace

A portable Coder workspace for operating an existing Coder deployment
from the CLI. Built on the `codercom/oss-dogfood` image, so the workspace
ships with `coder`, `terraform`, `git`, `gh`, the `docker` CLI, Node, Go,
and Python out of the box. The workspace owner is auto-logged into the
CLI via the `coder/coder-login` registry module — no session tokens to
paste, no unauthenticated `coder` commands.

This makes the template a natural fit for AI agents (Claude Code, etc.)
that need to manage a deployment on your behalf: the agent gets a
signed-in `coder` CLI plus the `coder-templates` and `coder-modules`
skills wired into `~/.claude/skills/`, ready to push templates, manage
workspaces, and inspect users or orgs.

## Prerequisites

- A Docker-capable provisioner on the target deployment.
- Outbound network access for the workspace to pull the dogfood image
  and the registry modules.

## Architecture

The template provisions a Docker volume (`docker_volume.home`) mounted at
`/home/coder` with `lifecycle { ignore_changes = all }` so your home
directory, SSH keys, and CLI config persist across restarts. The container
is started with the Coder agent init script and grants access to the host
Docker daemon via `host.docker.internal` (host gateway).

Modules pulled in on every start:

- `coder-login` — signs the workspace owner into the Coder CLI for the
  deployment the workspace lives on.
- `code-server` — browser-based editor rooted at `~/projects`.
- `git-clone` — optional; clones `git_repo_url` into `~/projects` on
  first start.
- `claude-code` — optional; installs the Claude Code CLI (see below).

## Using it from an agent

Once the workspace is up, `coder` is authenticated against the deployment
that provisioned it. From an agent or a shell you can run, for example:

```bash
coder templates list
coder workspaces list
coder users list
coder templates push <name> --directory .
coder ssh <workspace>
```

The `install_registry_skills` parameter (on by default) clones
`coder/registry` into `~/registry` and symlinks the `coder-templates` and
`coder-modules` agent skills into `~/.claude/skills/`, so an agent
authoring templates or modules from this workspace picks up the registry
contribution conventions automatically.

## Claude Code

Setting `enable_claude_code = true` installs the Claude Code CLI via the
official module. The module requires exactly one authentication method —
edit the `claude-code` module block in `main.tf` to pass
`anthropic_api_key`, `claude_code_oauth_token`, `enable_ai_gateway = true`
(Coder AI Gateway, Premium), or an override base URL.
