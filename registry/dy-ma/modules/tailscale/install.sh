#!/usr/bin/env bash
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[tailscale-install] $*" >&2; }
has() { command -v "$1" &> /dev/null; }

# Wait for apt locks to be released before touching apt, to avoid racing with
# other concurrent startup scripts (e.g. KasmVNC, code-server) that also run
# apt-get update at workspace boot.
wait_for_apt() {
  local timeout=120 elapsed=0
  while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      log "Warning: apt lock still held after ${timeout}s, proceeding anyway"
      break
    fi
    log "Waiting for apt lock to be released (${elapsed}s/${timeout}s)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

# ── Install Tailscale ─────────────────────────────────────────────────────────

if has tailscale; then
  log "Tailscale already installed ($(tailscale version 2> /dev/null | awk 'NR==1{print $1}')), skipping."
  exit 0
fi

log "Installing Tailscale..."
wait_for_apt
curl -fsSL https://tailscale.com/install.sh | sh
log "Installed: $(tailscale version | head -1)"
