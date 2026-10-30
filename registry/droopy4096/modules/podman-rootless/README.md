---
display_name: Rootless Podman
description: Configure rootless Podman with native overlay storage and a Docker-compatible socket in Kubernetes workspaces.
icon: ../../../../.icons/docker.svg
verified: false
tags: [helper, podman, docker, containers, kubernetes]
---

# Rootless Podman

Sets up [rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) inside a workspace so you can run and build containers without a privileged pod, Sysbox, or a VM runtime.

```tf
module "podman" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/podman-rootless/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

The module:

- Switches Podman to kernel overlayfs by writing `~/.config/containers/storage.conf` with an empty `mount_program`, so no `/dev/fuse` device plugin is needed. A `storage.conf` you manage yourself is left alone.
- Starts the Docker-compatible API (`podman system service`) on `/tmp/podman.sock` and exports `DOCKER_HOST`, so the docker CLI, Compose, and Testcontainers work unchanged.
- Exports `DOCKER_BUILDKIT=0`, because BuildKit can't start inside the workspace. `podman build` (Buildah) still supports `RUN --mount=type=cache` and secrets; `docker buildx` is not supported.
- Provides Buildah and Skopeo, installing them if the image lacks them and the script can run as root or with passwordless sudo. See [Buildah and Skopeo](#buildah-and-skopeo).

It does not install Podman itself or change the pod spec. Those belong to the image and template; see [Prerequisites](#prerequisites).

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
  source   = "registry.coder.com/droopy4096/podman-rootless/coder"
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
  source           = "registry.coder.com/droopy4096/podman-rootless/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  socket           = false
  disable_buildkit = false
}
```

## Buildah and Skopeo

`extra_tools` (default `["buildah", "skopeo"]`) makes both tools available next to Podman. They read the same storage and registry configuration as Podman, so an image built with `buildah` shows up in `podman images`, and `skopeo` can inspect or copy it through `containers-storage:`.

If a tool is missing, the install script installs it with apt, dnf, microdnf, yum, apk or zypper, but only when it runs as root or the user has passwordless sudo. Pods that run as non-root (as in the example above) usually have neither, so the script prints a warning and Podman setup continues. Baking the packages into the image avoids that, and avoids reinstalling them on every start. They are called `buildah` and `skopeo` on Debian, Ubuntu, Fedora, Red Hat UBI 9 and Alpine:

```dockerfile
# Debian or Ubuntu
RUN apt-get update && apt-get install -y --no-install-recommends buildah skopeo
# Fedora or UBI 9 (microdnf on ubi-minimal)
RUN dnf install -y buildah skopeo
# Alpine
RUN apk add --no-cache buildah skopeo
```

Set `extra_tools = []` to skip them.

## Dev containers

Rootless Podman supports one level of nesting. The dev container `docker-in-docker` feature won't work; use `docker-outside-of-docker`, mount `/tmp/podman.sock` to `/var/run/docker-host.sock`, and run `devcontainer up --buildkit never`.

## Troubleshooting

Logs live in `~/.coder-modules/droopy4096/podman-rootless/logs/` (`install.log`, `start.log`, `podman-service.log`). `podman info` shows whether Podman runs rootless and which storage driver it uses.
