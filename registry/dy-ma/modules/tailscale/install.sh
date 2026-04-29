#!/usr/bin/env bash
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[tailscale-install] $*" >&2; }
has() { command -v "$1" &> /dev/null; }

# ── Install Tailscale ─────────────────────────────────────────────────────────

if has tailscale; then
  log "Tailscale already installed ($(tailscale version 2> /dev/null | awk 'NR==1{print $1}')), skipping."
  exit 0
fi

log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
log "Installed: $(tailscale version | head -1)"
