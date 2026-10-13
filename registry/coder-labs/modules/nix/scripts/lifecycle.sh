# shellcheck shell=bash

_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

command -v nix_log > /dev/null 2>&1 || nix_log() {
  shift
  printf '%s\n' "$*"
}

nix_redact_url() {
  printf '%s' "$1" | sed -E 's#(https?://)[^/@[:space:]]+@#\1[redacted]@#g'
}

nix_strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\r$//'
}

nix_filter_log() {
  local line prefix
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(nix_redact_url "$line")
    case "$line" in
      *$'\033'*) line=$(printf '%s' "$line" | nix_strip_ansi) ;;
    esac
    case "$line" in
      "") continue ;;
      " "*/nix/store/*) continue ;;
      "these "*" will be "*: | "this "*" will be "*:)
        case "$line" in
          "these "*) line=${line#these } ;;
          "this "*) line="1 ${line#this }" ;;
        esac
        printf '%s\n' "${line%:}"
        continue
        ;;
      "remote: "* | "From "* | " "*".."*"->"*) continue ;;
      *"> "*)
        prefix=${line%%> *}
        case "$prefix" in
          "" | *[[:space:]]*) ;;
          *) continue ;;
        esac
        ;;
    esac

    case "${line%% *}" in
      [a-z]*[!a-zA-Z:]*) ;;
      [a-z]*) line="${line^}" ;;
    esac

    printf '%s\n' "$line"
  done
}

nix_run_logged() {
  local rc=0 out line
  out="$(mktemp)"
  "$@" > "$out" 2>&1 || rc=$?
  nix_filter_log < "$out" | while IFS= read -r line; do nix_log info "$line"; done
  rm -f "$out"
  return "$rc"
}

nix_checkout_dirty() {
  [ -n "$(_sudo git -C "$NIX_FLAKE_DIR" status --porcelain --untracked-files=no 2> /dev/null | head -1)" ]
}

nix_checkout_rev() {
  _sudo git -C "$NIX_FLAKE_DIR" rev-parse HEAD 2> /dev/null || true
}

nix_own_checkout() {
  local owner
  owner=$(stat -c %U "$NIX_FLAKE_DIR" 2> /dev/null || echo root)
  _sudo chown -R "$owner" "$NIX_FLAKE_DIR" 2> /dev/null || true
}

nix_checkout_branch() {
  _sudo git -C "$NIX_FLAKE_DIR" rev-parse --abbrev-ref HEAD 2> /dev/null || true
}

# Uncommitted (tracked or untracked, non-ignored) changes, or commits that are
# on no remote-tracking branch.
nix_checkout_has_local_work() {
  [ -n "$(_sudo git -C "$NIX_FLAKE_DIR" status --porcelain 2> /dev/null | head -1)" ] \
    || [ "$(_sudo git -C "$NIX_FLAKE_DIR" rev-list --count --branches --not --remotes 2> /dev/null || echo 1)" != 0 ]
}

# Clone into a temporary directory first, then replace the checkout's contents,
# so a failed clone leaves an existing checkout untouched.
nix_clone_checkout() {
  local url="$1" branch="$2" tmp rc=0
  tmp="$(_sudo mktemp -d)"
  if [ -n "$branch" ]; then
    nix_run_logged _sudo git clone --branch "$branch" "$url" "$tmp/repo" || rc=$?
  else
    nix_run_logged _sudo git clone "$url" "$tmp/repo" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    nix_log error "Could not clone $(nix_redact_url "$url")${branch:+ (branch $branch)} (git exited $rc)"
    nix_log error "Check the flake reference the template was pushed with: the repository has to exist and be readable from this instance."
    _sudo rm -rf "$tmp"
    return 1
  fi
  _sudo install -d -m 0755 "$NIX_FLAKE_DIR"
  _sudo find "$NIX_FLAKE_DIR" -mindepth 1 -delete
  _sudo tar -C "$tmp/repo" -cf - . | _sudo tar -C "$NIX_FLAKE_DIR" -xf -
  _sudo rm -rf "$tmp"
  nix_own_checkout
}

nix_sync_checkout() {
  local url="$1" branch="${2:-}" upstream_rev local_rev current_branch origin_url rc

  if [ ! -e "$NIX_FLAKE_DIR/flake.nix" ]; then
    nix_log info "Cloning $(nix_redact_url "$url") into $NIX_FLAKE_DIR"
    nix_clone_checkout "$url" "$branch"
    return
  fi

  # flake_ref now names a different repository.
  origin_url="$(_sudo git -C "$NIX_FLAKE_DIR" remote get-url origin 2> /dev/null || true)"
  if [ -n "$origin_url" ] && [ "$origin_url" != "$url" ]; then
    if nix_checkout_has_local_work; then
      nix_log warn "$NIX_FLAKE_DIR tracks $(nix_redact_url "$origin_url"), not $(nix_redact_url "$url"), and has local changes or unpushed commits; building it as-is"
      nix_log warn "Push or discard them, or delete $NIX_FLAKE_DIR, to switch to the new repository"
      return 0
    fi
    nix_log info "Flake repository changed to $(nix_redact_url "$url"); replacing $NIX_FLAKE_DIR"
    nix_clone_checkout "$url" "$branch"
    return
  fi

  current_branch="$(nix_checkout_branch)"
  [ -n "$branch" ] || branch="$current_branch"

  if nix_checkout_dirty; then
    nix_log info "$NIX_FLAKE_DIR has local changes; building those instead of $branch"
    return 0
  fi

  if [ -n "$current_branch" ] && [ "$current_branch" != "$branch" ]; then
    nix_log warn "$NIX_FLAKE_DIR is on $current_branch, not $branch; building $current_branch"
    nix_log warn "Check out $branch there, or delete $NIX_FLAKE_DIR to start from the remote"
    return 0
  fi

  # Root fetch writes into .git even when it fails.
  rc=0
  nix_run_logged _sudo git -C "$NIX_FLAKE_DIR" fetch --quiet origin "$branch" || rc=$?
  nix_own_checkout
  if [ "$rc" -ne 0 ]; then
    nix_log warn "Could not reach the remote; building the existing checkout"
    return 0
  fi

  local_rev="$(nix_checkout_rev)"
  upstream_rev="$(_sudo git -C "$NIX_FLAKE_DIR" rev-parse FETCH_HEAD 2> /dev/null || true)"
  [ -n "$upstream_rev" ] || return 0
  [ "$local_rev" != "$upstream_rev" ] || return 0

  # Fast-forward only. A checkout carrying local commits is left alone.
  if _sudo git -C "$NIX_FLAKE_DIR" merge-base --is-ancestor "$local_rev" "$upstream_rev" 2> /dev/null; then
    nix_log info "Updating $NIX_FLAKE_DIR to ${upstream_rev:0:12}"
    _sudo git -C "$NIX_FLAKE_DIR" reset --hard --quiet "$upstream_rev"
    nix_own_checkout
  else
    nix_log info "$NIX_FLAKE_DIR has local commits; building those instead of $branch"
  fi
}

nix_recorded_rev() {
  cat "$NIX_STATE_DIR/flake.rev" 2> /dev/null || true
}

nix_record_rev() {
  _sudo install -d -m 0755 "$NIX_STATE_DIR"
  printf '%s\n' "$1" | _sudo tee "$NIX_STATE_DIR/flake.rev" > /dev/null
}

# Compares against /run/current-system, the *activated* system, and not
nix_pending_generation() {
  [ "$(readlink -f /run/current-system)" != "$(readlink -f /nix/var/nix/profiles/system)" ]
}

nix_needs_rebuild() {
  local rev

  if nix_checkout_dirty; then
    printf 'dirty#%s' "$NIX_FLAKE_ATTR"
    return 0
  fi

  rev="$(nix_checkout_rev)"
  [ -n "$rev" ] || rev="unknown"
  printf '%s#%s' "$rev" "$NIX_FLAKE_ATTR"

  [ "$rev#$NIX_FLAKE_ATTR" = "$(nix_recorded_rev)" ] || return 0
  nix_pending_generation
}

# Build the local checkout as-is; no remote override or lock-file suppression.
nix_apply() {
  local operation="$1" transcript="$2" rc

  _sudo install -d -m 0755 "$NIX_LOG_DIR"
  _sudo install -m 0644 /dev/null "$transcript"
  _sudo ln -sfn "$transcript" "$NIX_LOG_DIR/rebuild-latest.log"

  # stdbuf must run under _sudo; it cannot exec a shell function.
  set +e
  _sudo nixos-rebuild "$operation" \
    --flake "$NIX_FLAKE_DIR#$NIX_FLAKE_ATTR" \
    --print-build-logs \
    2>&1 | _sudo stdbuf -oL tee -a "$transcript" | nix_filter_log \
    | while IFS= read -r line; do nix_log info "$line"; done
  rc=${PIPESTATUS[0]}
  set -e

  return "$rc"
}

nix_lock() {
  local lock="$NIX_STATE_DIR/rebuild.lock"
  _sudo install -d -m 0755 "$NIX_STATE_DIR"
  # Mode 0666 so the workspace user can take the same advisory lock as root.
  [ -e "$lock" ] || _sudo install -m 0666 /dev/null "$lock"
  exec 9> "$lock"
  if [ "${1:-wait}" = "nowait" ]; then
    flock -n 9
  else
    flock 9
  fi
}

# Write nix.conf text to a file atomically (0644), or remove the file when the
# text is empty. Prints "changed" or "unchanged"; returns non-zero, printing
# nothing, when the file could not be written or removed. Every step is checked
# explicitly: callers use `$(nix_write_conf ...) || ...`, which disables
# errexit and the ERR trap inside this function.
nix_write_conf() {
  local text="$1" file="$2" tmp
  if [ -z "$text" ]; then
    if [ -e "$file" ] || [ -L "$file" ]; then
      rm -f "$file" || return 1
      echo changed
    else
      echo unchanged
    fi
    return 0
  fi
  if [ -f "$file" ] && [ "$(cat "$file" 2> /dev/null)" = "$text" ]; then
    echo unchanged
    return 0
  fi
  [ -d "$(dirname "$file")" ] || install -d -m 0755 "$(dirname "$file")" 2> /dev/null || return 1
  tmp=$(mktemp "$file.XXXXXX" 2> /dev/null) || return 1
  if ! { printf '%s\n' "$text" > "$tmp" && chmod 0644 "$tmp" && mv -f "$tmp" "$file"; } 2> /dev/null; then
    rm -f "$tmp"
    return 1
  fi
  echo changed
}

# Append `!include <target>` to a nix.conf unless the line is already there.
# Existing content is never modified. Prints "added", "present", or "skipped"
# when the file is a symlink (e.g. managed by home-manager) or not writable.
nix_ensure_include() {
  local file="$1" target="$2" line
  line="!include $target"
  if [ -L "$file" ] || { [ -e "$file" ] && [ ! -w "$file" ]; }; then
    echo skipped
    return 0
  fi
  if [ -f "$file" ] && grep -qxF -- "$line" "$file"; then
    echo present
    return 0
  fi
  if ! { [ -d "$(dirname "$file")" ] || install -d -m 0755 "$(dirname "$file")" 2> /dev/null; }; then
    echo skipped
    return 0
  fi
  # Start on a fresh line if the file does not end with a newline.
  if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then
    printf '\n' >> "$file"
  fi
  if ! printf '# Added by the coder-labs/nix Coder module.\n%s\n' "$line" >> "$file" 2> /dev/null; then
    echo skipped
    return 0
  fi
  echo added
}
