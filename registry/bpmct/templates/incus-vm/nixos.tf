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

  # The nix-shared Incus profile mounts /data/nix (the full nix tree) from the
  # ThinkStation HDD at /nix-host inside this VM (via virtiofs/9p). We configure
  # nix to use /nix-host as the store root (URI: local?root=/nix-host), so all
  # package installs/builds go to the large shared HDD store at /data/nix/store.
  # The VM's own /nix/store (sda2) is used only for the OS itself.
  #
  # /nix/var/nix (DB, channels, socket) stays local to each VM.
  # Deduplication is automatic since nix store paths are content-addressed.
  nix.settings.trusted-users = [ "root" "$WUSER" ];
  nix.settings.allowed-users = [ "*" ];
  nix.settings.store = "local?root=/nix-host&state=/nix/var/nix&log=/nix/var/log/nix";

  # Create the mountpoint for the virtiofs/9p share (Incus mounts it here).
  system.activationScripts.nix-host-dir = ''
    mkdir -p /nix-host
  '';

  # Bind-mount /nix-host/nix/store over /nix/store so that result symlinks
  # from nix-build (which point to /nix/store/...) resolve correctly.
  #
  # Background: the VM image bakes the NixOS closure into /nix/store on sda2
  # (ext4, read-only).  The nix-shared profile mounts the ThinkStation HDD
  # share at /nix-host/nix via 9p.  nix.settings.store redirects nix daemon
  # writes to /nix-host/nix/store, but the result symlinks still say
  # /nix/store/... — which points at the stale ext4 partition.  The bind mount
  # below shadows the ext4 mount with the live HDD store, so both nix internals
  # and result symlinks work correctly.
  #
  # We order after local-fs.target (the 9p virtio share is mounted as part of
  # local-fs) and before nix-daemon so the daemon always sees the unified store.
  systemd.mounts = [
    {
      what       = "/nix-host/nix/store";
      where      = "/nix/store";
      type       = "none";
      options    = "bind";
      after      = [ "local-fs.target" ];
      before     = [ "nix-daemon.service" ];
      wantedBy   = [ "multi-user.target" ];
      requiredBy = [ "nix-daemon.service" ];
    }
  ];

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

      # Pre-patch /etc/nix/nix.conf with the correct store URI before nixos-rebuild
      # runs.  The coder.nix module sets nix.settings.store via NixOS options, but
      # those only take effect *after* nixos-rebuild switch completes — meaning the
      # rebuild itself would use the old nix.conf.  By patching the file now we
      # ensure the correct store (with local DB paths to avoid SQLite-over-9p
      # errors) is in effect for the rebuild.
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "if [ -d /nix-host/nix/store ]; then \
           echo 'nix-host mount detected, patching /etc/nix/nix.conf store URI...'; \
           STORE_URI='local?root=/nix-host&state=/nix/var/nix&log=/nix/var/log/nix'; \
           if grep -q '^store' /etc/nix/nix.conf; then \
             sed -i \"s|^store.*|store = \$STORE_URI|\" /etc/nix/nix.conf; \
           else \
             echo \"store = \$STORE_URI\" >> /etc/nix/nix.conf; \
           fi; \
           echo 'nix.conf store line:'; grep store /etc/nix/nix.conf; \
         fi"

      # Restore the nixos channel if it was wiped (e.g. by a previous failed
      # provisioning run that mounted the host /nix/var/nix over the VM's).
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "NIX_CHANNEL_URL=https://channels.nixos.org/nixos-25.11; \
         CHANNEL_LINK=/nix/var/nix/profiles/per-user/root/channels; \
         if [ ! -e \"\$CHANNEL_LINK\" ]; then \
           echo 'Restoring nixos channel...'; \
           nix-channel --add \"\$NIX_CHANNEL_URL\" nixos; \
           nix-channel --update nixos; \
         fi"

      echo "Running nixos-rebuild switch (this may take a few minutes)..."
      # Pre-apply the bind mount before nixos-rebuild so the newly built system
      # derivation lands in /nix/store (via the HDD store) and activation can
      # find it.  Without this, nixos-rebuild writes to /nix-host/nix/store but
      # activation checks /nix/store (the ext4 ro partition) and aborts.
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "if [ -d /nix-host/nix/store ]; then \
           /run/current-system/sw/bin/mount --bind /nix-host/nix/store /nix/store 2>/dev/null && echo 'Bind-mounted /nix-host/nix/store -> /nix/store' || echo 'Bind mount skipped (already mounted or not needed)'; \
         fi"
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
