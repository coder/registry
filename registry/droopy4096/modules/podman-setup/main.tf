terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "native_overlay" {
  description = "Use kernel overlayfs instead of fuse-overlayfs by clearing `mount_program` in `~/.config/containers/storage.conf`. Requires kernel 5.13+ and a graph root (`~/.local/share/containers`) on a real filesystem such as a PVC or emptyDir, not the container's own overlay root."
  type        = bool
  default     = true
}

variable "socket" {
  description = "Start the Docker-compatible API (`podman system service`) and export `DOCKER_HOST`, so the docker CLI, Compose, Testcontainers, and the dev container `docker-outside-of-docker` feature talk to Podman."
  type        = bool
  default     = true
}

variable "socket_path" {
  description = "Unix socket path for the Docker-compatible API."
  type        = string
  default     = "/tmp/podman.sock"

  validation {
    condition     = startswith(var.socket_path, "/")
    error_message = "socket_path must be an absolute path."
  }
}

variable "disable_buildkit" {
  description = "Export `DOCKER_BUILDKIT=0` so `docker build` and `docker compose build` use the classic builder. BuildKit can't start inside a rootless workspace; `podman build` is unaffected."
  type        = bool
  default     = true
}

variable "docker_shim" {
  description = "When the image has no `docker` command, link `docker` to `podman` in `/usr/local/bin` (directly or with passwordless sudo), falling back to `~/.local/bin`. An existing docker CLI is kept; it reaches Podman through `DOCKER_HOST`."
  type        = bool
  default     = true
}

variable "required_tools" {
  description = "Commands the image must provide besides `podman`, for example `[\"buildah\", \"skopeo\"]`. The install script fails and lists every missing one. This module installs nothing."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.required_tools : can(regex("^[A-Za-z0-9._+-]+$", t))])
    error_message = "required_tools entries must be plain command names."
  }
}

variable "icon" {
  description = "Icon for the scripts this module creates."
  type        = string
  default     = "/emojis/1f9ad.png"
}

locals {
  module_directory = "$HOME/.coder-modules/droopy4096/podman-setup"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_NATIVE_OVERLAY = tostring(var.native_overlay)
    ARG_REQUIRED_TOOLS = join(" ", distinct(var.required_tools))
    ARG_DOCKER_SHIM    = tostring(var.docker_shim)
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_SOCKET_PATH = var.socket_path
    ARG_LOG_FILE    = "${local.module_directory}/logs/podman-service.log"
  })
}

resource "coder_env" "docker_host" {
  count    = var.socket ? 1 : 0
  agent_id = var.agent_id
  name     = "DOCKER_HOST"
  value    = "unix://${var.socket_path}"
}

resource "coder_env" "docker_buildkit" {
  count    = var.disable_buildkit ? 1 : 0
  agent_id = var.agent_id
  name     = "DOCKER_BUILDKIT"
  value    = "0"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "Podman"
  icon                = var.icon
  install_script      = local.install_script
  start_script        = var.socket ? local.start_script : null
}

output "docker_host" {
  description = "Value exported as `DOCKER_HOST`, or an empty string when `socket = false`."
  value       = var.socket ? "unix://${var.socket_path}" : ""
}

output "scripts" {
  description = "Ordered `coder exp sync` names of the scripts this module creates, for serializing downstream scripts (for example, wait for the socket before running Testcontainers)."
  value       = module.coder_utils.scripts
}
