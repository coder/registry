---
display_name: Docker Containers
description: Provision Docker containers as Coder workspaces
icon: ../../../../.icons/docker.svg
verified: true
tags: [docker, container]
---

# Remote Development on Docker Containers

Provision Docker containers as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

<!-- TODO: Add screenshot -->

## Prerequisites

### Workspace image

This template exposes an `image` variable that controls which container image workspaces run. The image determines what tools, languages, and runtimes are available in the workspace out of the box, so it has a major impact on the developer experience.

Some options to consider:

| Image                                                                                             | Tradeoffs                                                                              |
| ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| [`codercom/example-base:ubuntu`](https://github.com/coder/images/tree/main/images/base) (default) | Minimal and lightweight, but may not include many tools developers expect by default   |
| [`codercom/example-universal:ubuntu`](https://github.com/coder/images/tree/main/images/universal) | Catch-all image with many languages and tools available, but larger and slower to pull |

More language-specific images (Go, Java, Node.js, and more) are available in [coder/images](https://github.com/coder/images), and the [devcontainers/images](https://github.com/devcontainers/images) collection is another good source of ready-made development images. You can also build your own image to pre-bake the exact tools your team needs. See [Coder's image management docs](https://coder.com/docs/admin/templates/managing-templates/image-management) for additional guidance.

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

- Docker image (built by Docker socket and kept locally)
- Docker container pod (ephemeral)
- Docker volume (persistent on `/home/coder`)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the container image. Alternatively, individual developers can [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.

### Editing the image

Edit the `Dockerfile` and run `coder templates push` to update workspaces.
