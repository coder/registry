---
display_name: Docker Build
description: Build Docker containers from Dockerfile as Coder workspaces
icon: ../../../../.icons/docker.svg
verified: true
tags: [docker, container, dockerfile]
---

# Remote Development on Docker Containers (Build from Dockerfile)

> [!NOTE]
> This template is designed to be a starting point for testing purposes.
> In a production environment, you would want to move away from storing the Dockerfile in-template and move towards using a centralized image registry.

Build and provision Docker containers from a Dockerfile as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

This template builds a custom Docker image from the included Dockerfile, allowing you to customize the development environment by modifying the Dockerfile rather than using a pre-built image.

<!-- TODO: Add screenshot -->

## Prerequisites

### Infrastructure

#### Running Coder inside Docker

If you installed Coder as a container within Docker, you will have to do the following things:

- Make the the Docker socket available to the container
  - **(recommended) Mount `/var/run/docker.sock` via `--mount`/`volume`**
  - _(advanced) Restrict the Docker socket via https://github.com/Tecnativa/docker-socket-proxy_
- Set `--group-add`/`group_add` to the GID of the Docker group on the **host** machine
  - You can get the GID by running `getent group docker` on the **host** machine

If you are using `docker-compose`, here is an example on how to do those things (don't forget to edit `group_add`!):
https://github.com/coder/coder/blob/0bfe0d63aec83ae438bdcb77e306effd100dba3d/docker-compose.yaml#L16-L23

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

- Docker image (built from Dockerfile and kept locally)
- Docker container pod (ephemeral)
- Docker volume (persistent on `/home/coder`)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the `build/Dockerfile`. Alternatively, individual developers can [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform and Dockerfile to extend the template to support your use case.

### Editing the image

Edit the `build/Dockerfile` and run `coder templates push` to update workspaces. The image will be rebuilt automatically when the Dockerfile changes.

## Difference from the standard Docker template

The main difference between this template and the standard Docker template is:

- **Standard Docker template**: Uses a pre-built image (e.g., `codercom/enterprise-base:ubuntu`)
- **Docker Build template**: Builds a custom image from the included `build/Dockerfile`

This allows for more customization of the development environment while maintaining the same workspace functionality.
