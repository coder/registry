---
display_name: Podman Setup
description: Configure the rootless Podman an image provides, with native overlay storage, a Docker-compatible socket, and checks for required tools.
icon: ../../../../.icons/docker.svg
verified: false
tags: [helper, podman, docker, containers, kubernetes]
---

# Podman Setup

Configures the [rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) that the workspace image provides, so you can run and build containers without a privileged pod, Sysbox, or a VM runtime.

```tf
module "podman" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/podman-setup/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

The module:

- Switches Podman to kernel overlayfs by writing `~/.config/containers/storage.conf` with an empty `mount_program`, so no `/dev/fuse` device plugin is needed. A `storage.conf` you manage yourself is left alone.
- Starts the Docker-compatible API (`podman system service`) on `/tmp/podman.sock` and exports `DOCKER_HOST`, so the docker CLI, Compose, and Testcontainers work unchanged.
- Makes `docker` run Podman when the image has no docker CLI, by linking `docker` to `podman`. See [Docker CLI](#docker-cli).
- Exports `DOCKER_BUILDKIT=0`, because BuildKit can't start inside the workspace. `podman build` (Buildah) still supports `RUN --mount=type=cache` and secrets; `docker buildx` is not supported.
- Checks that `podman`, and anything listed in `required_tools` (for example `buildah` and `skopeo`), is in the image, and fails with one clear error listing what is missing. See [Required tools](#required-tools).

It installs nothing and doesn't change the pod spec. Podman, any other tools, and the rootless prerequisites come from the image and template; see [Prerequisites](#prerequisites).

## Prerequisites

Follow Coder's [rootless Podman guide](https://coder.com/docs/admin/templates/extending-templates/docker-in-workspaces#rootless-podman). In short:

- **Image**: Podman, `uidmap` (with `newuidmap`/`newgidmap` capabilities), and `/etc/subuid` + `/etc/subgid` entries for the workspace user. [`codercom/example-podman:ubuntu`](https://github.com/coder/images/tree/main/images/podman) has all of these.
- **Nodes**: user namespaces enabled (`user.max_user_namespaces` > 0) and kernel 5.13+ for native overlay.
- **Pod**: runs as a non-root user (for example `run_as_user = 1000`, `fs_group = 1000`, `run_as_non_root = true`).
- **Storage**: `~/.local/share/containers` on a real filesystem, not the container's overlay root. Either mount a persistent volume at `/home/coder` (images persist across restarts) or an `emptyDir` at `/home/coder/.local/share/containers` (images are lost on stop).

With a persistent home volume, set `fs_group_change_policy = "OnRootMismatch"` in the pod `security_context`. Otherwise the kubelet recursively changes group ownership on every start, which rewrites the ownership of rootless image layers and slows startup as the store grows.

## Examples

### Kubernetes pod with a persistent home

```tf
module "podman" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/podman-setup/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

resource "kubernetes_pod_v1" "main" {
  # ...
  spec {
    security_context {
      run_as_user            = 1000
      run_as_group           = 1000
      run_as_non_root        = true
      fs_group               = 1000
      fs_group_change_policy = "OnRootMismatch"
    }
    container {
      name    = "dev"
      image   = "codercom/example-podman:ubuntu"
      command = ["sh", "-c", coder_agent.main.init_script]
      # ...
      volume_mount {
        name       = "home"
        mount_path = "/home/coder"
      }
    }
    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
      }
    }
  }
}
```

### Podman CLI only

Skip the socket and keep BuildKit settings untouched:

```tf
module "podman" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/droopy4096/podman-setup/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  socket           = false
  disable_buildkit = false
}
```

## Required tools

The module checks for `podman` on every start. Add anything else your workspaces depend on to `required_tools`, and the install script fails with one error that lists every missing command and the package to add:

```tf
module "podman" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/droopy4096/podman-setup/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  required_tools = ["buildah", "skopeo"]
}
```

Buildah and Skopeo read the same storage and registry configuration as Podman, so an image built with `buildah` shows up in `podman images`, and `skopeo` can inspect or copy it through `containers-storage:`. The packages have the same names on Debian, Ubuntu, Fedora, Red Hat UBI 9 and Alpine:

```dockerfile
# Debian or Ubuntu
RUN apt-get update && apt-get install -y --no-install-recommends buildah skopeo
# Fedora or UBI 9 (microdnf on ubi-minimal)
RUN dnf install -y buildah skopeo
# Alpine
RUN apk add --no-cache buildah skopeo
```

When Buildah or Skopeo is present, the install log records its version even if it isn't required.

## Docker CLI

With `docker_shim = true` (the default), the install script makes sure `docker` works:

- **No docker command in the image**: links `docker` to `podman` in `/usr/local/bin`, using passwordless `sudo` when the directory isn't writable. Without either, it links `~/.local/bin/docker` and warns if `~/.local/bin` isn't on `PATH`.
- **`docker` already links to Podman** (as in `codercom/example-podman:ubuntu`) or **a real docker CLI is installed**: leaves it alone. A real docker CLI, Docker Compose v2 and Testcontainers talk to Podman through `DOCKER_HOST` when `socket = true`.

`docker compose` through the symlink runs `podman compose`, which needs `docker-compose` or `podman-compose` in the image; the install log notes when neither is present. Set `docker_shim = false` to leave `docker` untouched.

## Network access and air-gapped environments

The module downloads nothing, so it works unchanged in air-gapped clusters. Image pulls by Podman, Buildah and Skopeo follow `registries.conf` (`/etc/containers/registries.conf` or `~/.config/containers/registries.conf`), where you can point public registries at an internal mirror.

## Dev containers

Rootless Podman supports one level of nesting. The dev container `docker-in-docker` feature won't work; use `docker-outside-of-docker`, mount `/tmp/podman.sock` to `/var/run/docker-host.sock`, and run `devcontainer up --buildkit never`.

## Troubleshooting

Logs live in `~/.coder-modules/droopy4096/podman-setup/logs/` (`install.log`, `start.log`, `podman-service.log`). `podman info` shows whether Podman runs rootless and which storage driver it uses.
