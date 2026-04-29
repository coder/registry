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
#
# Binary cache: an Attic server runs on the ThinkStation at 10.78.3.1:8080.
# VMs use it as a substituter so builds are shared across all NixOS VMs.
# A post-build hook auto-pushes new store paths to the cache after each build.

locals {
  # NixOS images on images.linuxcontainers.org use just "nixos/25.11" with no
  # arch suffix in the alias — unlike Ubuntu which appends e.g. "/amd64".
  is_nixos = startswith(data.coder_parameter.image.value, "nixos/")

  # Attic binary cache on ThinkStation (incusbr0 gateway, always reachable from VMs).
  attic_url       = "http://10.78.3.1:8080"
  attic_cache     = "main"
  attic_pubkey    = "main:+O2V0KSKDos1vrth+xucxa7DCW3UX05JVwc+2WKKEUw="
  # Push token — pull+push to main cache, no admin rights.
  attic_push_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjI2NDA5Nzk5NjQsIm5iZiI6MTc3NzA2NjM2NCwic3ViIjoibml4b3Mtdm0iLCJodHRwczovL2p3dC5hdHRpYy5ycy92MSI6eyJjYWNoZXMiOnsibWFpbiI6eyJyIjoxLCJ3IjoxfX19fQ.GhVnty_hfoEjp1WHId9a8UUGahtbDJpTL-gt7tJqkwM"
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
      ATTIC_URL="${local.attic_url}"
      ATTIC_CACHE="${local.attic_cache}"
      ATTIC_PUBKEY="${local.attic_pubkey}"
      ATTIC_TOKEN="${local.attic_push_token}"

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

      # Write the attic post-build hook script.
      # Runs after every nix build and pushes new store paths to the cache.
      # attic-client uses `attic login <server> <url> <token>` + `attic push <server>:<cache>`.
      printf '#!/bin/sh\nset -eu\nexport HOME=/root\nATTIC_URL="%s"\nATTIC_CACHE="%s"\n[ -f /etc/nix/attic-token ] || exit 0\nTOKEN=$(cat /etc/nix/attic-token)\n/run/current-system/sw/bin/attic login thinkstation "$ATTIC_URL" "$TOKEN" 2>/dev/null || true\n/run/current-system/sw/bin/attic push "thinkstation:$ATTIC_CACHE" $OUT_PATHS 2>&1 || true\n' \
        "$ATTIC_URL" "$ATTIC_CACHE" \
        | incus file push - "$REMOTE:$INSTANCE/etc/nix/post-build-hook.sh" --mode 0755

      # Write the attic push token (readable by nix-daemon = root)
      printf '%s' "$ATTIC_TOKEN" \
        | incus file push - "$REMOTE:$INSTANCE/etc/nix/attic-token" --mode 0600

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

  nix.settings.trusted-users = [ "root" "$WUSER" ];
  nix.settings.allowed-users = [ "*" ];

  # Make <nixpkgs> resolve for all users via NIX_PATH, and allow unfree
  # packages by default so nix-build works without extra env vars.
  nix.nixPath = [ "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos" ];
  nixpkgs.config.allowUnfree = true;

  # Attic binary cache on ThinkStation — shared across all NixOS VMs.
  # Builds are fetched from here on cache hit; new builds are pushed via
  # the post-build hook below.
  nix.settings.extra-substituters = [ "$ATTIC_URL/$ATTIC_CACHE" ];
  nix.settings.extra-trusted-public-keys = [ "$ATTIC_PUBKEY" ];

  # Auto-push every build result to the Attic cache.
  nix.settings.post-build-hook = "/etc/nix/post-build-hook.sh";

  # attic client — needed by the post-build hook.
  environment.systemPackages = [ pkgs.attic-client ];

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

      # Restore the nixos channel for root if missing — this is what NIX_PATH
      # points at so <nixpkgs> resolves for all users.
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "NIX_CHANNEL_URL=https://channels.nixos.org/nixos-25.11; \
         CHANNEL_LINK=/nix/var/nix/profiles/per-user/root/channels; \
         if [ ! -e \"\$CHANNEL_LINK/nixos\" ]; then \
           echo 'Restoring nixos channel...'; \
           nix-channel --add \"\$NIX_CHANNEL_URL\" nixos; \
           nix-channel --update nixos; \
         fi"

      # Set up user-level nixpkgs config (allowUnfree) so nix-build works
      # without NIXPKGS_ALLOW_UNFREE=1 for the workspace user.
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "mkdir -p /home/$WUSER/.config/nixpkgs && \
         if [ ! -f /home/$WUSER/.config/nixpkgs/config.nix ]; then \
           printf '{ allowUnfree = true; }\n' > /home/$WUSER/.config/nixpkgs/config.nix; \
           chown -R 1000:1000 /home/$WUSER/.config; \
         fi"

      echo "Running nixos-rebuild switch (this may take a few minutes)..."
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -l -c \
        "nixos-rebuild switch; EC=\$?; [ \$EC -eq 0 ] || [ \$EC -eq 4 ] || exit \$EC"

      echo "Restarting coder-agent service..."
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "systemctl daemon-reload; systemctl restart coder-agent.service; sleep 3; systemctl status coder-agent.service || true"

      # Ensure home dir ownership
      incus exec "$REMOTE:$INSTANCE" -- \
        env PATH=/run/current-system/sw/bin /run/current-system/sw/bin/bash -c \
        "mkdir -p /home/$WUSER && chown 1000:1000 /home/$WUSER && chmod 755 /home/$WUSER"

      echo "NixOS provisioning complete."
    EOT
  }
}
