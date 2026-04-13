---
display_name: Docker TeX Live
description: Provision Docker containers with TeX Live, code-server
icon: ../../../../.icons/texlive.png
tags: [docker, texlive]
---

# TeX Live Development on Docker Containers

Provision Docker containers pre-configured for TeX development as [Coder workspaces](https://coder.com/docs/workspaces) with this template.

Each workspace comes with:

- **TeX Live** — TeX Live is a comprehensive, cross-platform distribution for TeX and LaTeX systems that provides all necessary programs, macro packages, and fonts for professional typesetting.
- **code-server** — VS Code in the browser for general editing.

The workspace is based on the [TeX Live](https://www.tug.org/texlive) image. It provides nearly all packages from the [Comprehensive TeX Archive Network (CTAN)](https://www.ctan.org), although some non-free packages may be restricted.

## Prerequisites

### Infrastructure

#### Running Coder inside Docker

If you installed Coder as a container within Docker, you will have to do the following things:

- Make the Docker socket available to the container
  - **(recommended) Mount `/var/run/docker.sock` via `--mount`/`volume`**
  - _(advanced) Restrict the Docker socket via https://github.com/Tecnativa/docker-socket-proxy_
- Set `--group-add`/`group_add` to the GID of the Docker group on the **host** machine
  - You can get the GID by running `getent group docker` on the **host** machine

#### Running Coder outside of Docker

If you installed Coder as a system package, the VM you run Coder on must have a running Docker socket and the `coder` user must be added to the Docker group:

```bash
# Add coder user to Docker group
sudo adduser coder docker

# Restart Coder server
sudo systemctl restart coder

# Test Docker
sudo -u coder docker ps
```

## Architecture

This template provisions the following resources:

- Docker image (built from `build/Dockerfile`, extending `registry.gitlab.com/islandoftex/images/texlive` with system dependencies)
- Docker container (ephemeral — destroyed on workspace stop)
- Docker volume (persistent on `/home/texlive`)

When the workspace restarts, tools and files outside `/home/texlive` are not persisted.

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform to extend it for your use case.

## Customization

The continuous integration is scheduled to rebuild all Docker images weekly. Hence, pulling the latest image will provide you with an at most one week old snapshot of TeX Live including all packages. You can manually update within the container by running `tlmgr update --self --all`.

Each of the weekly builds is tagged with `TL{RELEASE}-{YEAR}-{MONTH}-{DAY}-{HOUR}-{MINUTE}` apart from being latest for one week. If you want to have reproducible builds or happen to find a regression in a later image you can still revert to a date that worked, e.g. `TL2019-2019-08-01-08-14 or latest`.

- [Container Registry TeX Live](https://gitlab.com/islandoftex/images/texlive/container_registry)
- [Dockerhub TeX Live](https://hub.docker.com/r/texlive/texlive)

### Installing additional TeX packages

If you want to update packages from CTAN after installation, see these [examples of using tlmgr](https://tug.org/texlive/doc/tlmgr.html#EXAMPLES). This is not required, or even necessarily recommended; it's up to you to decide if it makes sense to get continuing updates in your particular situation.

Typically the main binaries are not updated in TeX Live between major releases. If you want to get updates for LuaTeX and other packages and programs that aren't officially released yet, they may be available in the [TLContrib repository](http://contrib.texlive.info), or you may need to [compile the sources](https://tug.org/texlive/svn) yourself.

### Adding system dependencies

The `build/Dockerfile` extends the `registry.gitlab.com/islandoftex/images/texlive` base image with system packages required by modules (e.g. `curl` for code-server). If you add modules that need additional system-level tools, add them to the `Dockerfile`:

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
  curl \
  inkscape \
  unzip \
  vim \
  wget \
  your-package-here \
 && rm -rf /var/lib/apt/lists/*
```
