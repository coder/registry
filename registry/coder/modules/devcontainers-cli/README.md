---
display_name: devcontainers-cli
description: devcontainers-cli module provides an easy way to install @devcontainers/cli into a workspace
icon: ../../../../.icons/devcontainers.svg
verified: true
tags: [devcontainers]
---

# devcontainers-cli

This module installs [`@devcontainers/cli`](https://github.com/devcontainers/cli) when a Coder agent starts. It makes the `devcontainer` command available in the agent-managed binary directory, without requiring `sudo`, so workspace startup scripts and users can run Dev Container commands.

The module uses the first available package manager in this order: Yarn, npm, then pnpm. Docker and one of these package managers must already be installed in the workspace image. If `devcontainer` is already on `PATH`, the module keeps that installation and skips downloading the package.

```tf
module "devcontainers-cli" {
  source             = "registry.coder.com/coder/devcontainers-cli/coder"
  version            = "1.2.0"
  agent_id           = coder_agent.example.id
  start_blocks_login = false
}
```

## Configuration

By default, the module installs the `latest` npm dist-tag without delaying workspace login. Set `start_blocks_login = true` when `devcontainer` must be ready before a user can connect.

## Pin a CLI version

Use an exact version for reproducible workspace builds:

```tf
module "devcontainers-cli" {
  source                    = "registry.coder.com/coder/devcontainers-cli/coder"
  version                   = "1.2.0"
  agent_id                  = coder_agent.example.id
  devcontainers_cli_version = "0.80.0"
}
```

## Use an internal registry

Configure the selected package manager's registry and authentication before this module's installation script runs, under the same workspace user. The module uses that existing configuration without overriding the registry or storing credentials.

For example, preconfigure npm's user-level `.npmrc` with your internal mirror:

```ini
registry=https://registry.example.com/npm/
```

For Artifactory, the [JFrog OAuth module](../jfrog-oauth) can configure npm and pnpm authentication. Ensure that configuration has completed before the devcontainers CLI installation starts. If Yarn is installed, configure Yarn's registry and authentication as well, since this module selects Yarn first.

## Network and air-gapped environments

During installation, the selected package manager contacts its configured registry to resolve and download `@devcontainers/cli` and its dependencies. An internal mirror must serve both package metadata and referenced package artifacts.

The module makes no network requests after installation. Commands run through `devcontainer` can still contact the Docker daemon, image registries, and sources referenced by the workspace's Dev Container configuration. For a fully air-gapped workspace, bake the CLI and required container artifacts into the image; when `devcontainer` is already on `PATH`, this module skips installation.
