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

# Wrap apt-get so that any apt-get calls made by the Tailscale install script
# (or any other subprocess) automatically wait for apt locks instead of failing
# immediately. APT::Lock::Timeout covers /var/lib/apt/lists/lock (apt-get update)
# and DPkg::Lock::Timeout covers /var/lib/dpkg/lock-frontend (apt-get install).
if has apt-get; then
  orig_apt=$(command -v apt-get)
  apt_wrap=$(mktemp -d)
  cat >"$apt_wrap/apt-get" <<EOF
#!/usr/bin/env bash
exec "$orig_apt" -o APT::Lock::Timeout=120 -o DPkg::Lock::Timeout=120 "\$@"
EOF
  chmod +x "$apt_wrap/apt-get"
  export PATH="$apt_wrap:$PATH"
fi

curl -fsSL https://tailscale.com/install.sh | sh
log "Installed: $(tailscale version | head -1)"
