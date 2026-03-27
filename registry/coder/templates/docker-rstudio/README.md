---
display_name: Docker RStudio
description: Provision Docker containers with RStudio, code-server, and RMarkdown
icon: ../../../../.icons/rstudio.svg
verified: true
tags: [docker, rstudio, r, rmarkdown, code-server]
---

# R Development on Docker Containers

Provision Docker containers pre-configured for R development as [Coder workspaces](https://coder.com/docs/workspaces) with this template.

Each workspace comes with:

- **RStudio Server** — full-featured R IDE in the browser.
- **code-server** — VS Code in the browser for general editing.
- **RMarkdown** — author reproducible documents, reports, and presentations.

The workspace is based on the [rocker/rstudio](https://rocker-project.org/) image, which ships R and RStudio Server pre-installed.

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

```sh
# Add coder user to Docker group
sudo adduser coder docker

# Restart Coder server
sudo systemctl restart coder

# Test Docker
sudo -u coder docker ps
```

## Architecture

This template provisions the following resources:

- Docker image (`rocker/rstudio` — includes R and RStudio Server)
- Docker container (ephemeral — destroyed on workspace stop)
- Docker volume (persistent on `/home/rstudio`)

When the workspace restarts, tools and files outside `/home/rstudio` are not persisted. The R library path defaults to a subdirectory of the home folder, so installed packages (including RMarkdown) survive restarts.

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform to extend it for your use case.

## Customization

### Changing the R version

Set the `rstudio_version` variable to any valid [rocker/rstudio tag](https://hub.docker.com/r/rocker/rstudio/tags) (for example `4.4.2`, `4.3`, or `latest`).

### Installing additional R packages

Add `install.packages()` calls to the `startup_script` in the `coder_agent` resource. Packages installed under the home directory are persisted across restarts.

### Adding LaTeX for PDF rendering

RMarkdown can render PDF output when LaTeX is available. Add the following to the startup script to install TinyTeX:

```sh
R --quiet -e "if (!require('tinytex', quietly = TRUE)) { install.packages('tinytex', repos = 'https://cloud.r-project.org'); tinytex::install_tinytex() }"
```
