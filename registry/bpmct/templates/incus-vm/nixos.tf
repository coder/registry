# NixOS-specific provisioning for incus-vm workspaces.
#
# NixOS doesn't support cloud-init, so instead we:
#   1. Push the coder agent init script and env file via incus file push
#   2. Generate /etc/nixos/coder.nix declaring the user + coder-agent service
#   3. Patch configuration.nix to import coder.nix
#   4. Run nixos-rebuild switch
#   5. Restart coder-agent.service with the fresh token
#
# This provisioner runs on every workspace start (null_resource is recreated
# each cycle), which also handles token rotation.

locals {
  # NixOS images on images.linuxcontainers.org use just "nixos/25.11" with no
  # arch suffix in the alias — unlike Ubuntu which appends e.g. "/amd64".
  is_nixos = startswith(data.coder_parameter.image.value, "nixos/")
}

resource "null_resource" "provision_nixos" {
  count = data.coder_workspace.me.start_count == 1 && local.is_nixos ? 1 : 0

  triggers = {
    agent_token = local.agent_token
    instance    = incus_instance.dev.name
  }

  depends_on = [incus_instance.dev]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      REMOTE="${local.incus_remote}"
      INSTANCE="${incus_instance.dev.name}"
      WUSER="${local.workspace_user}"
      ARCH="${data.coder_parameter.host.value == "ThinkStation" ? "amd64" : "arm64"}"

      echo "Waiting for NixOS VM incus-agent to be ready..."
      for i in $(seq 1 60); do
        if incus exec "$REMOTE:$INSTANCE" -- true 2>/dev/null; then
          echo "incus-agent ready after $i attempts"
          break
        fi
        echo "Attempt $i: incus-agent not ready yet, waiting..."
        sleep 5
      done

      # Write init script into the VM
      incus exec "$REMOTE:$INSTANCE" -- mkdir -p /opt/coder
      echo "${base64encode(local.agent_init_script)}" | base64 -d | incus file push - "$REMOTE:$INSTANCE/opt/coder/init"
      incus exec "$REMOTE:$INSTANCE" -- chmod 755 /opt/coder/init

      # Write env file into the VM
      printf 'CODER_AGENT_TOKEN=${local.agent_token}\nCODER_AGENT_URL=${data.coder_workspace.me.access_url}\n' \
        | incus file push - "$REMOTE:$INSTANCE/opt/coder/init.env" --mode 0600

      # Write the NixOS coder module, substituting the username
      NIXMOD=$(cat <<NIXMOD_EOF
{ config, pkgs, lib, ... }:
{
  users.users."$WUSER" = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/$WUSER";
    shell = pkgs.bash;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Use the shared host nix-daemon instead of running our own.
  # The host mounts /nix (from /data/nix) into this VM via the nix-shared
  # Incus profile, so the daemon socket is already present at
  # /nix/var/nix/daemon-socket/socket.
  nix.settings.trusted-users = [ "root" "$WUSER" ];
  nix.settings.allowed-users = [ "*" ];

  # Disable the VM's own nix-daemon — we use the host one.
  systemd.services.nix-daemon.enable = lib.mkForce false;
  systemd.sockets.nix-daemon.enable = lib.mkForce false;

  # Override the default read-only bind of /nix/store from the VM's own
  # disk partition. With the host /nix already mounted at /nix via virtio-fs,
  # we just bind /nix/store from there (read-write so the daemon can write).
  fileSystems."/nix/store" = lib.mkForce {
    device = "/nix/store";
    options = [ "bind" "rw" ];
    depends = [ "/nix" ];
  };

  systemd.services.coder-agent = {
    description = "Coder Agent";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "$WUSER";
      EnvironmentFile = "/opt/coder/init.env";
      ExecStart = "/opt/coder/init";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/local/bin:/usr/bin:/bin";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 90;
      KillMode = "process";
      OOMScoreAdjust = -900;
      SyslogIdentifier = "coder-agent";
    };
  };
}
NIXMOD_EOF
)
      echo "$NIXMOD" | incus file push - "$REMOTE:$INSTANCE/etc/nixos/coder.nix"

      # Patch configuration.nix to import coder.nix if not already imported
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "grep -q coder.nix /etc/nixos/configuration.nix || \
         sed -i 's|imports = \[|imports = [\n    ./coder.nix|' /etc/nixos/configuration.nix"

      echo "Running nixos-rebuild switch (this may take a few minutes)..."
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -l -c \
        "nixos-rebuild switch; EC=\$?; [ \$EC -eq 0 ] || [ \$EC -eq 4 ] || exit \$EC"

      echo "Restarting coder-agent service..."
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "systemctl daemon-reload; systemctl restart coder-agent.service; sleep 3; systemctl status coder-agent.service || true"

      # Ensure home dir ownership (nixos-rebuild will have created the user home)
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "mkdir -p /home/$WUSER && chown 1000:1000 /home/$WUSER && chmod 755 /home/$WUSER"

      echo "NixOS provisioning complete."
    EOT
  }
}
