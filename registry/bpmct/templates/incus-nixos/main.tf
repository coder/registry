terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "incus" {}

variable "arch" {
  description = "CPU architecture of the VM host. Set this when pushing the template to match your Incus host. Valid values: amd64, arm64."
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "arch must be amd64 or arm64."
  }
}

variable "storage_pool" {
  description = "Incus storage pool for the root disk. Run `incus storage list` on the host to see available pools."
  type        = string
  default     = "default"
}

variable "nixos_channel" {
  description = "NixOS channel to use for nixos-rebuild. Must match the image version (e.g. nixos-25.11)."
  type        = string
  default     = "nixos-25.11"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Number of vCPUs."
  type         = "number"
  default      = 2
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/cpu-3.svg"
  mutable      = true
  order        = 1
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  type         = "number"
  default      = 4
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 2
  validation {
    min = 1
    max = 64
  }
}

data "coder_parameter" "disk" {
  name         = "disk"
  display_name = "Disk (GB)"
  type         = "number"
  default      = 30
  icon         = "/icon/database.svg"
  mutable      = true
  order        = 3
  validation {
    min = 10
    max = 500
  }
}

locals {
  workspace_user    = lower(data.coder_workspace_owner.me.name)
  agent_token       = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].token : ""
  agent_init_script = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].init_script : ""

  # NixOS images on images.linuxcontainers.org use "nixos/<ver>" with no arch suffix.
  # The channel version (e.g. "25.11") is extracted from var.nixos_channel.
  nixos_version = replace(var.nixos_channel, "nixos-", "")
  image_alias   = "nixos/${local.nixos_version}"

  # PATH required for incus exec commands on NixOS VMs. The Nix store is not
  # on the default system PATH until after the first nixos-rebuild switch.
  nix_path = "/nix/var/nix/profiles/system/sw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin"
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = var.arch
  os    = "linux"
}

resource "incus_image" "nixos" {
  source_image = {
    remote       = "images"
    name         = local.image_alias
    type         = "virtual-machine"
    architecture = var.arch == "amd64" ? "x86_64" : "aarch64"
  }
}

resource "incus_instance" "dev" {
  running = data.coder_workspace.me.start_count == 1
  name    = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  image   = incus_image.nixos.fingerprint
  type    = "virtual-machine"

  config = {
    "limits.cpu"             = tostring(data.coder_parameter.cpu.value)
    "limits.memory"          = "${data.coder_parameter.memory.value}GiB"
    "security.secureboot"    = false
    "boot.autostart"         = data.coder_workspace.me.start_count == 1
    "user.coder-agent-token" = local.agent_token
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = "${data.coder_parameter.disk.value}GiB"
    }
  }

  lifecycle {
    ignore_changes = [
      config["user.coder-agent-token"],
      image,
    ]
  }
}

# NixOS does not support cloud-init. Provisioning steps:
#   1. Wait for the incus-agent to be ready (virtio serial channel).
#   2. Push the Coder agent binary (/opt/coder/init) and token env file.
#   3. On first boot: write coder.nix and an updated configuration.nix
#      that imports the Incus VM module, then run nixos-rebuild switch.
#      Leave a marker so subsequent starts skip the rebuild.
#   4. On subsequent starts: overwrite init.env + restart coder-agent.

resource "null_resource" "provision" {
  count = data.coder_workspace.me.start_count

  triggers = {
    agent_token = local.agent_token
    instance    = incus_instance.dev.name
  }

  depends_on = [incus_instance.dev]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      INSTANCE="${incus_instance.dev.name}"
      WUSER="${local.workspace_user}"
      NIX_PATH="${local.nix_path}"
      CHANNEL="${var.nixos_channel}"

      echo "Waiting for incus-agent..."
      for i in $(seq 1 60); do
        incus exec "$INSTANCE" -- true 2>/dev/null && break
        echo "  attempt $i/60..."
        sleep 5
      done

      echo "Pushing Coder agent binary..."
      TMPDIR=$(mktemp -d)
      echo "${base64encode(local.agent_init_script)}" | base64 -d > "$TMPDIR/init"
      chmod 755 "$TMPDIR/init"
      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" mkdir -p /opt/coder
      incus file push "$TMPDIR/init" "$INSTANCE/opt/coder/init"
      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" chmod 755 /opt/coder/init
      rm -rf "$TMPDIR"

      printf 'CODER_AGENT_TOKEN=${local.agent_token}\nCODER_AGENT_URL=${data.coder_workspace.me.access_url}\n' \
        | incus file push - "$INSTANCE/opt/coder/init.env" --mode 0600

      # Fast path: already provisioned -- just rotate token and restart.
      if incus exec "$INSTANCE" -- test -f /etc/nixos/.coder-provisioned 2>/dev/null; then
        echo "Already provisioned; restarting coder-agent..."
        incus exec "$INSTANCE" -- env PATH="$NIX_PATH" systemctl restart coder-agent.service
        echo "Done."
        exit 0
      fi

      # First boot: write NixOS config and rebuild.
      echo "Writing /etc/nixos/coder.nix..."
      cat <<'NIXEOF' | incus exec "$INSTANCE" -- env PATH="$NIX_PATH" bash -c 'cat > /etc/nixos/coder.nix'
{ config, pkgs, lib, ... }:
{
  users.users."${local.workspace_user}" = {
    isNormalUser = true;
    uid          = 1000;
    home         = "/home/${local.workspace_user}";
    shell        = pkgs.bash;
    extraGroups  = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "root" "${local.workspace_user}" ];

  systemd.services.coder-agent = {
    description = "Coder Agent";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User             = "${local.workspace_user}";
      EnvironmentFile  = "/opt/coder/init.env";
      ExecStart        = "/opt/coder/init";
      Environment      = "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/local/bin:/usr/bin:/bin";
      Restart          = "always";
      RestartSec       = 10;
      TimeoutStopSec   = 90;
      KillMode         = "process";
      OOMScoreAdjust   = -900;
      SyslogIdentifier = "coder-agent";
    };
  };
}
NIXEOF

      echo "Writing /etc/nixos/configuration.nix..."
      cat <<'NIXEOF' | incus exec "$INSTANCE" -- env PATH="$NIX_PATH" bash -c 'cat > /etc/nixos/configuration.nix'
{ modulesPath, ... }:
{
  imports = [
    "$${modulesPath}/virtualisation/incus-virtual-machine.nix"
    ./incus.nix
    ./coder.nix
  ];

  systemd.network = {
    enable = true;
    networks."50-enp5s0" = {
      matchConfig.Name = "enp5s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  system.stateVersion = "${local.nixos_version}";
}
NIXEOF

      echo "Restoring nixos channel if needed..."
      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" HOME=/root bash -c "
        if [ ! -e /nix/var/nix/profiles/per-user/root/channels/nixos ]; then
          nix-channel --add https://channels.nixos.org/$CHANNEL nixos
          nix-channel --update nixos
        fi
      "

      echo "Running nixos-rebuild switch..."
      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" HOME=/root bash -c "
        NIXOS_CH=\$(ls -d /nix/var/nix/profiles/per-user/root/channels/nixos 2>/dev/null || echo '')
        nixos-rebuild switch -I nixpkgs=\"\$NIXOS_CH\" -I nixos-config=/etc/nixos/configuration.nix \
          || { EC=\$?; [ \$EC -eq 4 ] || exit \$EC; }
      "

      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" touch /etc/nixos/.coder-provisioned
      incus exec "$INSTANCE" -- env PATH="$NIX_PATH" bash -c \
        "mkdir -p /home/$WUSER && chown 1000:1000 /home/$WUSER"

      echo "NixOS provisioning complete."
    EOT
  }
}
