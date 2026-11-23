terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

# Uses the provisioner's Incus client configuration ($HOME/.config/incus):
# its default remote, unless `remote` names another one.
provider "incus" {}

variable "remote" {
  description = "Incus remote to create workspaces on, as named in the provisioner's Incus client configuration. Empty uses its default remote."
  type        = string
  default     = ""
}

variable "project" {
  description = "Incus project to create workspaces in. Empty uses the remote's default project."
  type        = string
  default     = ""
}

variable "arch" {
  description = "CPU architecture of the Incus host: `amd64` or `arm64`. Selects the image, the agent binary and `$ARCH` in `flake_attr`."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "arch must be amd64 or arm64."
  }
}

variable "storage_pool" {
  description = "Storage pool for the root disk. Empty uses the pool of the default profile's root disk."
  type        = string
  default     = ""
}

variable "flake_ref" {
  description = <<-EOT
    Git reference to the NixOS configuration, in the form `nix` itself
    accepts: `https://host/org/repo`, optionally with a `git+` prefix and a
    `?ref=` branch. Without `?ref=` the remote's default branch is used.

    The configuration must be committed -- a Git flake reference only ever
    sees committed files.
  EOT
  type        = string
  default     = "https://github.com/coder/nixos-example-flake"
}

variable "flake_attr" {
  description = "`nixosConfigurations` attribute to build. `$ARCH` is replaced with `x86_64` or `aarch64` to match `arch`."
  type        = string
  default     = "coder-workspace-incus-$ARCH"
}

variable "nixos_release" {
  description = <<-EOT
    NixOS release of the `images:nixos/<release>` image new workspaces boot
    from. Only affects newly created workspaces; packages and the kernel come
    from the flake's own nixpkgs pin.
  EOT
  type        = string
  default     = "26.05"
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Number of vCPUs."
  type         = "number"
  default      = 2
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 1

  validation {
    min = 1
    max = 32
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GiB)"
  description  = "4 GiB is the smallest that works: a rebuild that has to compile anything will exhaust less."
  type         = "number"
  default      = 4
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 2

  validation {
    min = 4
    max = 128
  }
}

data "coder_parameter" "root_volume_size" {
  name         = "root_volume_size"
  display_name = "Root disk size (GiB)"
  description  = "Holds the Nix store as well as /home. Can be increased later."
  type         = "number"
  default      = 50
  icon         = "/icon/database.svg"
  mutable      = true
  order        = 3

  validation {
    min       = 20
    max       = 2000
    monotonic = "increasing"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "incus_profile" "default" {
  name    = "default"
  remote  = local.remote
  project = local.project
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = var.arch
  os    = "linux"
  auth  = "token"
  # The first boot rebuilds NixOS before starting the agent.
  connection_timeout = 1200

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600
    timeout      = 30
    script       = "coder stat disk --path $HOME"
  }
  # Include staged-but-not-activated generations in the agent metadata.
  metadata {
    key          = "nixos"
    display_name = "NixOS version"
    interval     = 60
    timeout      = 10
    script       = module.nix.version_command
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
  order    = 1
}

# IDE binaries need nix-ld in the flake; the example enables it.
module "jetbrains-gateway" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains-gateway/coder"
  version    = "~> 1.2"
  agent_id   = coder_agent.main[0].id
  agent_name = "main"
  arch       = var.arch
  folder     = "/home/coder"
  # All listed IDEs have both x86 and ARM builds.
  jetbrains_ides = ["IU", "PY", "GO", "WS"]
  default        = "IU"
  latest         = true
  order          = 2
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
}

locals {
  remote     = var.remote == "" ? null : var.remote
  project    = var.project == "" ? null : var.project
  nix_arch   = var.arch == "arm64" ? "aarch64" : "x86_64"
  flake_attr = replace(var.flake_attr, "$ARCH", local.nix_arch)
  image      = "images:nixos/${var.nixos_release}"

  storage_pool = var.storage_pool != "" ? var.storage_pool : one([
    for device in data.incus_profile.default.device : device.properties.pool
    if device.type == "disk" && lookup(device.properties, "path", "") == "/"
  ])

  # The image ships no git, which the boot rebuild needs to clone the flake.
  # Its channel substitutes one from cache.nixos.org in seconds; the flake
  # itself then provides git from the first rebuild on.
  boot_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v git >/dev/null; then
      channel=/nix/var/nix/profiles/per-user/root/channels/nixos
      if [ -e "$channel" ]; then
        git_pkg=$(nix-build "$channel" -A git --no-out-link)
      else
        git_pkg=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths nixpkgs#git)
      fi
      export PATH="$git_pkg/bin:$PATH"
    fi
    ${module.nix.boot_script}
  EOT
}

module "nix" {
  source  = "registry.coder.com/coder-labs/nix/coder"
  version = "~> 1.0"

  config = {
    extra-substituters        = ["https://nix-community.cachix.org"]
    extra-trusted-public-keys = ["nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="]
  }

  nixos = {
    flake_ref  = var.flake_ref
    flake_attr = local.flake_attr
  }
}

module "incus-init" {
  source = "./modules/incus-init"

  agent_token       = try(coder_agent.main[0].token, "")
  agent_init_script = try(coder_agent.main[0].init_script, "")
  boot_script       = local.boot_script

  log_display_name = "NixOS"
  log_icon         = "/icon/nix.svg"
}

resource "incus_instance" "dev" {
  name    = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  remote  = local.remote
  project = local.project
  type    = "virtual-machine"
  image   = local.image
  running = data.coder_workspace.me.start_count == 1

  config = {
    "limits.cpu"    = tostring(data.coder_parameter.cpu.value)
    "limits.memory" = "${data.coder_parameter.memory.value}GiB"
    # The NixOS images are not signed for Secure Boot.
    "security.secureboot" = false
    "user.coder-owner"    = data.coder_workspace_owner.me.name
    "user.coder-name"     = data.coder_workspace.me.name
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = local.storage_pool
      size = "${data.coder_parameter.root_volume_size.value}GiB"
    }
  }

  # Exec needs the Incus agent, which the flake must keep enabled.
  wait_for {
    type = "agent"
  }

  # Every start mints a new agent token, which changes this entry and
  # reruns it; stopping removes it.
  exec = data.coder_workspace.me.start_count == 0 ? {} : {
    "coder-init" = {
      command     = module.incus-init.command
      environment = module.incus-init.environment
      timeout     = "5m"
    }
  }

  lifecycle {
    # New image releases must not replace an existing workspace and its disk.
    ignore_changes = [image]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = incus_instance.dev.name
  item {
    key   = "Image"
    value = local.image
  }
  item {
    key   = "Build logs location"
    value = module.nix.log_dir
  }
}
