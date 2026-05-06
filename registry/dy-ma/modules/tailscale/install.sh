#!/usr/bin/env bash
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[tailscale-install] $*" >&2; }
has() { command -v "$1" &> /dev/null; }

# ── Install Tailscale ─────────────────────────────────────────────────────────

if has tailscale; then
  log "Tailscale already installed ($(tailscale version 2>/dev/null | awk 'NR==1{print $1}')), skipping."
  exit 0
fi

log "Installing Tailscale..."

# Wrap apt-get so that any apt-get calls (including via sudo) automatically wait
# for apt locks instead of failing immediately. Written to /usr/local/bin/ so it
# takes precedence over /usr/bin/apt-get even when sudo resets PATH to secure_path.
# APT::Lock::Timeout covers /var/lib/apt/lists/lock (apt-get update).
# DPkg::Lock::Timeout covers /var/lib/dpkg/lock-frontend (apt-get install).
if has apt-get; then
  orig_apt=$(command -v apt-get)
  log "apt-get found at $orig_apt — installing lock-wait wrapper"
  sudo tee /usr/local/bin/apt-get >/dev/null <<EOF
#!/usr/bin/env bash
echo "[apt-get-wrapper] invoked with: \$*" >&2
exec "$orig_apt" -o APT::Lock::Timeout=120 -o DPkg::Lock::Timeout=120 "\$@"
EOF
  sudo chmod +x /usr/local/bin/apt-get
fi

curl -fsSL https://tailscale.com/install.sh | sh
log "Installed: $(tailscale version | head -1)"
