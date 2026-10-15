# shellcheck shell=bash
if [ -r "${CODER_LOG_LIBRARY:-}" ]; then
  # shellcheck source=/dev/null
  . "$CODER_LOG_LIBRARY"
else
  coder_log() {
    shift
    echo "$*"
  }
  coder_log_pipe() { cat; }
fi

STATE_DIR="${STATE_DIR:-/var/lib/coder-nixos}"
mkdir -p "$FLAKE_DIR" "$STATE_DIR" "$LOG_DIR"
# Root also needs to work in checkouts owned by the workspace user.
g() { git -c safe.directory="$FLAKE_DIR" -C "$FLAKE_DIR" "$@"; }

if [ ! -e "$FLAKE_DIR/.git" ]; then
  tmp=$(mktemp -d)
  if ! git clone -q --no-checkout ${FLAKE_BRANCH:+--branch "$FLAKE_BRANCH"} "$FLAKE_URL" "$tmp/repo" 2>&1 | coder_log_pipe info; then
    rm -rf "$tmp"
    coder_log error "Could not clone $FLAKE_URL"
    exit 1
  fi
  # Adopt the directory: tracked paths come from the flake; unrelated files stay.
  mv "$tmp/repo/.git" "$FLAKE_DIR/"
  rm -rf "$tmp"
  g reset -q --hard
elif [ "$(g remote get-url origin)" != "$FLAKE_URL" ]; then
  coder_log warn "$FLAKE_DIR tracks another repository; building it as-is. Delete it to switch."
elif [ -z "$(g status --porcelain --untracked-files=no)" ]; then
  if ! g pull -q --ff-only 2>&1 | coder_log_pipe info; then
    coder_log warn "Could not fast-forward $FLAKE_DIR; building it as-is."
  fi
fi
chown -hR --reference="$FLAKE_DIR" "$FLAKE_DIR" || coder_log warn "Could not restore checkout ownership."

rev="$(g rev-parse HEAD)#$FLAKE_ATTR"
if [ -z "$(g status --porcelain --untracked-files=no)" ] && [ "$rev" = "$(cat "$STATE_DIR/flake.rev" 2> /dev/null || true)" ]; then
  coder_log info "Configuration unchanged (${rev:0:12}); skipping rebuild."
  exit 0
fi

transcript="$LOG_DIR/rebuild-$(date -u +%Y%m%dT%H%M%SZ).log"
ln -sfn "$transcript" "$LOG_DIR/rebuild-latest.log"
coder_log info "Applying $FLAKE_DIR#$FLAKE_ATTR. ($transcript)"
if ! nixos-rebuild switch --flake "$FLAKE_DIR#$FLAKE_ATTR" -L 2>&1 | tee "$transcript" | coder_log_pipe info; then
  coder_log error "nixos-rebuild switch failed; the previous generation is still active."
  exit 1
fi
printf '%s\n' "$rev" > "$STATE_DIR/flake.rev"
coder_log info "Switch complete."
