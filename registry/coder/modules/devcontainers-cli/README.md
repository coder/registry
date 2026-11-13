---
display_name: devcontainers-cli
description: devcontainers-cli module provides an easy way to install @devcontainers/cli into a workspace
icon: ../../../../.icons/devcontainers.svg
verified: true
tags: [devcontainers]
---

# devcontainers-cli

This module installs [`@devcontainers/cli`](https://github.com/devcontainers/cli) when a Coder agent starts. It makes the `devcontainer` command available in the agent-managed binary directory, without requiring `sudo`, so workspace startup scripts and users can run Dev Container commands.

The module uses the first available package manager in this order: Yarn, npm, then pnpm. Bash, Docker, and one of these package managers must already be installed in the workspace image. If `devcontainer` is already on `PATH`, the module keeps that installation and skips downloading the package.

```tf
module "devcontainers-cli" {
  source             = "registry.coder.com/coder/devcontainers-cli/coder"
  version            = "2.0.0"
  agent_id           = coder_agent.example.id
  start_blocks_login = false
}
```

## Upgrading from 1.x

Version 2 requires Bash, the Coder Terraform provider 2.13 or later, and workspace support for `coder exp sync` because installation now runs through coder-utils. Update older provider constraints and workspace images before upgrading. The default remains `latest`, and `start_blocks_login` keeps its existing behavior.

## Configuration

By default, the module installs the `latest` npm dist-tag without delaying workspace login. Set `start_blocks_login = true` when `devcontainer` must be ready before a user can connect.

Installation uses [coder-utils](../coder-utils), which requires the Coder Terraform provider 2.13 or later and workspace support for `coder exp sync`. When login blocking is enabled, a separate script waits for this installation to finish. Installation errors remain visible on the installation script.

The installation script and log are stored under `$HOME/.coder-modules/coder/devcontainers-cli/scripts/install.sh` and `$HOME/.coder-modules/coder/devcontainers-cli/logs/install.log`.

## Pin a CLI version

Use an exact version for reproducible workspace builds. Both `0.80.0` and `v0.80.0` select the same release. Only `latest` and exact `X.Y.Z` / `vX.Y.Z` versions are accepted; ranges and other npm dist-tags are rejected:

```tf
module "devcontainers-cli" {
  source                    = "registry.coder.com/coder/devcontainers-cli/coder"
  version                   = "2.0.0"
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

For a template with a configured `module "jfrog"`, order the modules on the same agent:

```tf
module "devcontainers-cli" {
  source   = "registry.coder.com/coder/devcontainers-cli/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}

data "coder_script_order" "registry_before_devcontainers" {
  rule {
    run   = ["module.devcontainers-cli"]
    after = ["module.jfrog"]
    phase = "start"
  }
}
```

This example requires the Coder Terraform provider 2.20.0 or later and Coder control plane, provisioners, and workspace agents 2.39.0 or later. Older components can ignore the ordering declaration. The default success requirement prevents installation when the registry setup fails. Configure npm through JFrog and use a workspace image without Yarn, or configure Yarn separately before installation.

## Network and air-gapped environments

During installation, the selected package manager contacts its configured registry to resolve and download `@devcontainers/cli` and its dependencies. An internal mirror must serve both package metadata and referenced package artifacts.

The module makes no network requests after installation. Commands run through `devcontainer` can still contact the Docker daemon, image registries, and sources referenced by the workspace's Dev Container configuration. For a fully air-gapped workspace, bake the CLI and required container artifacts into the image; when `devcontainer` is already on `PATH`, this module skips installation.
