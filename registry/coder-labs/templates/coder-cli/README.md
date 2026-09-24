---
display_name: Coder CLI Workspace
description: A pre-authenticated Coder CLI workspace for operating a Coder deployment from the agent
icon: ../../../../.icons/coder.svg
verified: true
tags: [docker, container, cli, admin, agent]
---

# Coder CLI Workspace

A portable Docker workspace for operating an existing Coder deployment from the CLI. Built on `codercom/oss-dogfood`, the workspace ships the `coder` CLI pre-authenticated via the `coder/coder-login` module, so you can manage templates, workspaces, users, and orgs against the deployment that provisioned it without pasting session tokens.

## Prerequisites

- A Docker-capable provisioner on the target deployment.
- Outbound network access for the workspace to pull the dogfood image and the registry modules.

## Architecture

Provisions a Docker container with a persistent `/home/coder` volume, plus:

- `coder-login` — signs the workspace owner into the Coder CLI.
- `code-server` — browser-based editor rooted at `~/projects`.
- `git-clone` — optional; clones `git_repo_url` into `~/projects`.

## Using it from an agent

Once the workspace is up, `coder` is authenticated against the deployment that provisioned it:

```bash
coder templates list
coder workspaces list
coder templates push <name> --directory .
coder ssh <workspace>
```

The `install_registry_skills` parameter (on by default) clones `coder/registry` and links the `coder-templates` and `coder-modules` agent skills into `~/.claude/skills/` for agents authoring registry content.
