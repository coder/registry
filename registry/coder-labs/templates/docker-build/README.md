---
display_name: Docker Build
description: Build Docker containers from Dockerfile as Coder workspaces
icon: ../../../../.icons/docker.svg
verified: true
tags: [docker, container, dockerfile]
---

# Remote Development on Docker Containers (Build from Dockerfile)

Build and provision Docker containers from a Dockerfile as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

This template builds a custom Docker image from the included Dockerfile, allowing you to customize the development environment by modifying the Dockerfile rather than using a pre-built image.

<!-- TODO: Add screenshot -->

## Prerequisites

### Infrastructure

The VM you run Coder on must have a running Docker socket and the `coder` user must be added to the Docker group:

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
