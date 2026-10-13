# shellcheck shell=bash
# Shared by the Nix Develop app and prebuild: make `nix` available and apply
# the module's nix.conf settings. Expects NIX_CONF (may be empty).

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

# Appended, so an existing NIX_CONFIG is kept and ours applies last.
if [ -n "${NIX_CONF:-}" ]; then
  export NIX_CONFIG="${NIX_CONFIG:-}"$'\n'"$NIX_CONF"
fi
