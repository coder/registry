#!/usr/bin/env bash
set -Eeuo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null

git init -q -b main "$root/remote"
git -C "$root/remote" config user.email test@example.org
git -C "$root/remote" config user.name Test
printf 'initial\n' > "$root/remote/flake.nix"
git -C "$root/remote" add flake.nix
git -C "$root/remote" commit -qm initial

# Source the production functions while replacing privileged ownership with a probe.
# shellcheck source=lifecycle.sh
source "$here/lifecycle.sh"
nix_pending_generation() { false; }
_sudo() { "$@"; }
ownership_calls=0
nix_own_checkout() { ownership_calls=$((ownership_calls + 1)); }
NIX_FLAKE_DIR="$root/checkout"
NIX_STATE_DIR="$root/state"
NIX_FLAKE_ATTR=host-one
mkdir -p "$NIX_FLAKE_DIR"

nix_sync_checkout "file://$root/remote" main
[ -f "$NIX_FLAKE_DIR/flake.nix" ]
[ "$ownership_calls" -eq 1 ]
rev=$(nix_needs_rebuild)
[ "$rev" = "$(git -C "$NIX_FLAKE_DIR" rev-parse HEAD)#host-one" ]
nix_record_rev "$rev"
if nix_needs_rebuild > /dev/null; then
  echo 'unexpected rebuild' >&2
  exit 1
fi
NIX_FLAKE_ATTR=host-two
nix_needs_rebuild > /dev/null
nix_record_rev "$(nix_needs_rebuild)"
if nix_needs_rebuild > /dev/null; then
  echo 'unexpected attribute rebuild' >&2
  exit 1
fi

printf 'ignored by Git flake\n' > "$NIX_FLAKE_DIR/untracked"
if nix_needs_rebuild > /dev/null; then
  echo 'untracked file caused rebuild' >&2
  exit 1
fi
printf 'modified\n' > "$NIX_FLAKE_DIR/flake.nix"
nix_checkout_dirty
nix_needs_rebuild > /dev/null
git -C "$NIX_FLAKE_DIR" checkout -q -- flake.nix

printf 'updated\n' > "$root/remote/flake.nix"
git -C "$root/remote" commit -qam updated
nix_sync_checkout "file://$root/remote" main
[ "$(cat "$NIX_FLAKE_DIR/flake.nix")" = updated ]
[ "$ownership_calls" -eq 3 ]

before=$ownership_calls
nix_sync_checkout "file://$root/remote" main
[ "$ownership_calls" -eq "$((before + 1))" ]
before=$ownership_calls
# A failed fetch must still restore ownership.
git -C "$NIX_FLAKE_DIR" remote set-url origin file:///does-not-exist
nix_sync_checkout "file://$root/remote" main
[ "$ownership_calls" -eq "$((before + 1))" ]

redacted=$(printf 'fatal: https://user:token@example.org/repo\n' | nix_filter_log)
[[ "$redacted" == *'https://[redacted]@example.org/repo'* ]]
[[ "$redacted" != *token* ]]
[[ "$(nix_redact_url 'https://user:token@example.org/repo')" != *token* ]]
printf 'lifecycle tests passed\n'
