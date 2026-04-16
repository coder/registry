#!/usr/bin/env bash
set -euo pipefail

# Values injected by templatefile() in main.tf
TAILSCALE_API_URL="${TAILSCALE_API_URL}"
AUTH_KEY="${AUTH_KEY}"
OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID}"
OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET}"
TAILNET="${TAILNET}"
TS_HOSTNAME="${HOSTNAME}"
TAGS_JSON='${TAGS_JSON}'
TAGS_CSV="${TAGS_CSV}"
EPHEMERAL="${EPHEMERAL}"
PREAUTHORIZED="${PREAUTHORIZED}"
NETWORKING_MODE="${NETWORKING_MODE}"
SOCKS5_PORT="${SOCKS5_PORT}"
HTTP_PROXY_PORT="${HTTP_PROXY_PORT}"
ACCEPT_DNS="${ACCEPT_DNS}"
ACCEPT_ROUTES="${ACCEPT_ROUTES}"
ADVERTISE_ROUTES="${ADVERTISE_ROUTES}"
SSH="${SSH}"
STATE_DIR="${STATE_DIR}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[tailscale] $*" >&2; }
die()  { echo "[tailscale] ERROR: $*" >&2; exit 1; }
has()  { command -v "$1" &>/dev/null; }

# ── 1. Install Tailscale ──────────────────────────────────────────────────────

install_tailscale() {
  if has tailscale; then
    log "Tailscale already installed ($(tailscale version 2>/dev/null | awk 'NR==1{print $1}')), skipping."
    return
  fi

  log "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  log "Installed: $(tailscale version | head -1)"
}

# ── 2. Detect networking mode ─────────────────────────────────────────────────

resolve_networking_mode() {
  if [ "$NETWORKING_MODE" != "auto" ]; then
    echo "$NETWORKING_MODE"
    return
  fi
  if [ -c /dev/net/tun ] && [ -r /dev/net/tun ] && [ -w /dev/net/tun ]; then
    echo "kernel"
  else
    echo "userspace"
  fi
}

# ── 3. Start tailscaled ───────────────────────────────────────────────────────

start_tailscaled() {
  local mode="$1"

  # Build daemon flags
  local daemon_flags="--socket=/var/run/tailscale/tailscaled.sock"
  if [ -n "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR"
    daemon_flags="--state=$STATE_DIR/tailscaled.state $daemon_flags"
  fi
  if [ "$mode" = "userspace" ]; then
    daemon_flags="$daemon_flags --tun=userspace-networking"
    [ "$SOCKS5_PORT" != "0" ] && daemon_flags="$daemon_flags --socks5-server=localhost:$SOCKS5_PORT"
    [ "$HTTP_PROXY_PORT" != "0" ] && daemon_flags="$daemon_flags --outbound-http-proxy-listen=localhost:$HTTP_PROXY_PORT"
  fi

  if has systemctl && systemctl is-system-running --quiet 2>/dev/null; then
    if [ "$mode" = "userspace" ]; then
      # Drop-in override so we don't touch the upstream unit file
      sudo mkdir -p /etc/systemd/system/tailscaled.service.d
      printf '[Service]\nExecStart=\nExecStart=-/usr/sbin/tailscaled %s\n' \
        "$daemon_flags" \
        | sudo tee /etc/systemd/system/tailscaled.service.d/coder.conf >/dev/null
      sudo systemctl daemon-reload
    fi
    sudo systemctl enable --now tailscaled
    log "tailscaled started via systemd."
  else
    if pgrep -x tailscaled &>/dev/null; then
      log "tailscaled already running."
      return
    fi
    sudo mkdir -p /var/run/tailscale
    # shellcheck disable=SC2086
    sudo tailscaled $daemon_flags &>/tmp/tailscaled.log &
    sleep 2
    log "tailscaled started in background."
  fi
}

# ── 4. Generate a single-use auth key ─────────────────────────────────────────
# OAuth creds stay on this machine. We exchange them for a short-lived
# access token, use that to create a 5-minute single-use auth key, then
# discard both. The auth key is the only thing passed to tailscale up.

generate_auth_key() {
  has curl || die "curl is required."
  has jq   || die "jq is required."

  log "Fetching Tailscale access token..."
  local token_response
  token_response=$(curl -fsSL \
    -d "client_id=$OAUTH_CLIENT_ID" \
    -d "client_secret=$OAUTH_CLIENT_SECRET" \
    "$TAILSCALE_API_URL/api/v2/oauth/token") \
    || die "Failed to fetch OAuth access token."

  local access_token
  access_token=$(echo "$token_response" | jq -r '.access_token')
  [ "$access_token" = "null" ] || [ -z "$access_token" ] \
    && die "OAuth token response did not contain an access_token. Check your client ID and secret."

  log "Generating single-use auth key..."
  local key_response http_status
  key_response=$(curl -sSL -w "\n%%{http_code}" -X POST \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "{
      \"capabilities\": {
        \"devices\": {
          \"create\": {
            \"reusable\":      false,
            \"ephemeral\":     $EPHEMERAL,
            \"preauthorized\": $PREAUTHORIZED,
            \"tags\":          $TAGS_JSON
          }
        }
      },
      \"expirySeconds\": 300
    }" \
    "$TAILSCALE_API_URL/api/v2/tailnet/$TAILNET/keys")
  http_status=$(echo "$key_response" | tail -1)
  key_response=$(echo "$key_response" | head -n -1)
  if [ "$http_status" != "200" ]; then
    die "Failed to generate auth key (HTTP $http_status): $key_response"
  fi

  local auth_key
  auth_key=$(echo "$key_response" | jq -r '.key')
  [ "$auth_key" = "null" ] || [ -z "$auth_key" ] \
    && die "Key response did not contain a key. Response: $key_response"

  echo "$auth_key"
}

# ── 5. Bring up Tailscale ─────────────────────────────────────────────────────

bring_up() {
  local auth_key="$1"
  local mode="$2"

  # Assemble tailscale up flags
  local flags="--hostname=$TS_HOSTNAME"
  flags="$flags --advertise-tags=$TAGS_CSV"
  flags="$flags --accept-dns=$ACCEPT_DNS"
  [ "$TAILSCALE_API_URL" != "https://api.tailscale.com" ] && flags="$flags --login-server=$TAILSCALE_API_URL"
  [ "$ACCEPT_ROUTES" = "true" ]              && flags="$flags --accept-routes"
  [ -n "$ADVERTISE_ROUTES" ]                 && flags="$flags --advertise-routes=$ADVERTISE_ROUTES"
  [ "$SSH" = "true" ]                        && flags="$flags --ssh"
  [ "$mode" = "userspace" ]                  && flags="$flags --netfilter-mode=off"

  if [ -n "$auth_key" ]; then
    # shellcheck disable=SC2086
    sudo tailscale up --auth-key="$auth_key" $flags
  else
    # Already authenticated — re-apply flags only, no re-auth
    # shellcheck disable=SC2086
    sudo tailscale up $flags
  fi
}

# ── 6. Set proxy env vars (userspace only) ────────────────────────────────────

configure_proxy_env() {
  local mode="$1"
  [ "$mode" != "userspace" ] && return

  local lines=""
  [ "$SOCKS5_PORT" != "0" ] \
    && lines="$lines"$'\n'"export ALL_PROXY=socks5://localhost:$SOCKS5_PORT"
  [ "$HTTP_PROXY_PORT" != "0" ] \
    && lines="$lines"$'\n'"export http_proxy=http://localhost:$HTTP_PROXY_PORT"$'\n'"export https_proxy=http://localhost:$HTTP_PROXY_PORT"

  if [ -n "$lines" ]; then
    printf '# Set by tailscale Coder module%s\n' "$lines" \
      | sudo tee /etc/profile.d/tailscale-proxy.sh >/dev/null
    log "Proxy env vars written to /etc/profile.d/tailscale-proxy.sh"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  install_tailscale

  local mode
  mode=$(resolve_networking_mode)
  log "Networking mode: $mode"

  start_tailscaled "$mode"

  local auth_key=""
  if [ -n "$AUTH_KEY" ]; then
    log "Using provided auth key."
    auth_key="$AUTH_KEY"
  elif sudo tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
    log "Tailscale already connected. Re-applying flags..."
    # auth_key stays empty — bring_up will skip --auth-key
  else
    log "Not connected. Generating auth key via OAuth..."
    auth_key=$(generate_auth_key)
  fi

  bring_up "$auth_key" "$mode"
  configure_proxy_env "$mode"

  log "Status:"
  tailscale status
}

main
