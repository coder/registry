# shellcheck shell=bash
# Shared by the Nix Develop app and prebuild: make `nix` available. The
# module's nix.conf settings arrive through NIX_CONFIG (a coder_env).

# Non-NixOS installs only put nix on PATH for login shells.
if ! command -v nix > /dev/null 2>&1; then
  for nix_profile in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    if [ -r "$nix_profile" ]; then
      # The profile scripts are not written for `set -u`.
      set +u
      # shellcheck source=/dev/null
      . "$nix_profile"
      set -u
      break
    fi
  done
  unset nix_profile
fi
