# shellcheck shell=bash
#
# Nix flake lifecycle: sync a checkout, decide, apply. No EC2 and no Coder API
# calls. Inputs and contract: see README.md in this directory.

export NIX_CONFIG="experimental-features = nix-command flakes"

# Callers run as root from user-data and as the workspace user from a
# coder_script, so privilege handling belongs here rather than in each.
NIX_SUDO=""
[ "$(id -u)" -eq 0 ] || NIX_SUDO="sudo"

command -v nix_log > /dev/null 2>&1 || nix_log() {
  shift
  printf '%s\n' "$*"
}

nix_strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\r$//'
}

# Runs a command with its output filtered into the log, and returns the
# command's own status rather than the filter's.
#
# Not written as a pipeline: under `set -e` a failing pipeline ends the script
# there and then, before the caller can look at PIPESTATUS. That is how a
# clone of a flake reference that does not exist used to end a boot with
# nothing in the workspace log but "Cloning ..." -- the error message two
# lines further down was unreachable.
nix_run_logged() {
  local rc=0 out line
  out="$(mktemp)"
  "$@" > "$out" 2>&1 || rc=$?
  # Through nix_log rather than stdout: what git has to say about a clone it
  # could not do is the whole explanation, and stdout here is the instance's
  # journal, which is exactly the place the user cannot reach.
  nix_filter_log < "$out" | while IFS= read -r line; do nix_log info "$line"; done
  rm -f "$out"
  return "$rc"
}

# ---------------------------------------------------------------------------
# the checkout
# ---------------------------------------------------------------------------
#
# The configuration is a real git checkout at NIX_FLAKE_DIR (/etc/nixos), and
# that is what gets built. It is what makes a bare `nixos-rebuild switch`
# work, since nixos-rebuild looks for /etc/nixos/flake.nix on its own, and it
# means the configuration running the machine is something the user can read
# and edit.
#
# Local work is never discarded: we fast-forward only a clean checkout sitting
# on its tracking branch. A workspace whose configuration silently reverted on
# restart would be worse than one that drifts.
nix_checkout_dirty() {
  [ -n "$($NIX_SUDO git -C "$NIX_FLAKE_DIR" status --porcelain 2> /dev/null | head -1)" ]
}

nix_checkout_rev() {
  $NIX_SUDO git -C "$NIX_FLAKE_DIR" rev-parse HEAD 2> /dev/null || true
}

# Keep the whole tree owned by whoever owns the directory. We clone and fetch
# as root, which otherwise leaves .git root-owned inside a user-owned
# directory -- the user can edit files but every git command fails on
# .git/index.lock.
nix_own_checkout() {
  local owner
  owner=$(stat -c %U "$NIX_FLAKE_DIR" 2> /dev/null || echo root)
  $NIX_SUDO chown -R "$owner" "$NIX_FLAKE_DIR" 2> /dev/null || true
}

# The branch the checkout is actually on. With no `?ref=` in the flake
# reference there is nothing to ask but the checkout itself, and after a clone
# that is the remote's default branch.
nix_checkout_branch() {
  $NIX_SUDO git -C "$NIX_FLAKE_DIR" rev-parse --abbrev-ref HEAD 2> /dev/null || true
}

nix_sync_checkout() {
  local url="$1" branch="${2:-}" upstream_rev local_rev current_branch rc

  if [ ! -e "$NIX_FLAKE_DIR/flake.nix" ]; then
    nix_log info "Cloning $url into $NIX_FLAKE_DIR"
    $NIX_SUDO install -d -m 0755 "$NIX_FLAKE_DIR"
    # Clone into a temporary directory and move the contents, because the
    # directory already exists (systemd-tmpfiles creates it) and git refuses
    # to clone into a non-empty one.
    local tmp
    tmp="$($NIX_SUDO mktemp -d)"
    rc=0
    if [ -n "$branch" ]; then
      nix_run_logged $NIX_SUDO git clone --branch "$branch" "$url" "$tmp/repo" || rc=$?
    else
      nix_run_logged $NIX_SUDO git clone "$url" "$tmp/repo" || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
      nix_log error "Could not clone $url${branch:+ (branch $branch)} (git exited $rc)"
      nix_log error "Check the flake reference the template was pushed with: the repository has to exist and be readable from this instance."
      $NIX_SUDO rm -rf "$tmp"
      return 1
    fi
    $NIX_SUDO sh -c "cd '$tmp/repo' && tar cf - ." | $NIX_SUDO tar xf - -C "$NIX_FLAKE_DIR"
    $NIX_SUDO rm -rf "$tmp"
    nix_own_checkout
    return 0
  fi

  current_branch="$(nix_checkout_branch)"
  # An empty branch means "whatever this checkout tracks", which after the
  # clone above is the remote's default.
  [ -n "$branch" ] || branch="$current_branch"

  if nix_checkout_dirty; then
    nix_log info "$NIX_FLAKE_DIR has local changes; building those instead of $branch"
    return 0
  fi

  # Asking for a different branch than the checkout is on is not something to
  # resolve silently: the fast-forward below would fail its ancestry test and
  # report local commits, which is not what happened.
  if [ -n "$current_branch" ] && [ "$current_branch" != "$branch" ]; then
    nix_log warn "$NIX_FLAKE_DIR is on $current_branch, not $branch; building $current_branch"
    nix_log warn "Check out $branch there, or delete $NIX_FLAKE_DIR to start from the remote"
    return 0
  fi

  # Fetching as root writes into .git, so re-assert ownership afterwards.
  if ! nix_run_logged $NIX_SUDO git -C "$NIX_FLAKE_DIR" fetch --quiet origin "$branch"; then
    nix_log warn "Could not reach the remote; building the existing checkout"
    return 0
  fi

  local_rev="$(nix_checkout_rev)"
  upstream_rev="$($NIX_SUDO git -C "$NIX_FLAKE_DIR" rev-parse FETCH_HEAD 2> /dev/null || true)"
  [ -n "$upstream_rev" ] || return 0
  [ "$local_rev" != "$upstream_rev" ] || return 0

  # Fast-forward only. A checkout carrying local commits is left alone.
  if $NIX_SUDO git -C "$NIX_FLAKE_DIR" merge-base --is-ancestor "$local_rev" "$upstream_rev" 2> /dev/null; then
    nix_log info "Updating $NIX_FLAKE_DIR to ${upstream_rev:0:12}"
    $NIX_SUDO git -C "$NIX_FLAKE_DIR" reset --hard --quiet "$upstream_rev"
    nix_own_checkout
  else
    nix_log info "$NIX_FLAKE_DIR has local commits; building those instead of $branch"
  fi
}

# ---------------------------------------------------------------------------
# deciding
# ---------------------------------------------------------------------------

nix_recorded_rev() {
  cat "$NIX_STATE_DIR/flake.rev" 2> /dev/null || true
}

nix_record_rev() {
  $NIX_SUDO install -d -m 0755 "$NIX_STATE_DIR"
  printf '%s\n' "$1" | $NIX_SUDO tee "$NIX_STATE_DIR/flake.rev" > /dev/null
}

# True when a generation is the boot default but is not the running system,
# i.e. `boot` was used. A revision check alone would call that up to date.
#
# Compares against /run/current-system, the *activated* system, and not
# /run/booted-system, which is whatever the kernel booted. After a switch the
# booted symlink still points at the previous generation -- so using it here
# reports every freshly created workspace as needing a restart.
nix_pending_generation() {
  [ "$(readlink -f /run/current-system)" != "$(readlink -f /nix/var/nix/profiles/system)" ]
}

# Echoes a revision (or "dirty") and returns 0 when a rebuild is needed.
nix_needs_rebuild() {
  local rev

  if nix_checkout_dirty; then
    # Uncommitted work has no revision to compare, so always rebuild.
    printf 'dirty'
    return 0
  fi

  rev="$(nix_checkout_rev)"
  [ -n "$rev" ] || rev="unknown"
  printf '%s' "$rev"

  [ "$rev" = "$(nix_recorded_rev)" ] || return 0
  nix_pending_generation
}

# ---------------------------------------------------------------------------
# applying
# ---------------------------------------------------------------------------

# Drop the things that are noise rather than progress; everything else reaches
# the caller as nix wrote it. Nix's plain output is already the readable
# output -- every --log-format is byte-identical off a TTY.
nix_filter_log() {
  local line prefix
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *$'\033'*) line=$(printf '%s' "$line" | nix_strip_ansi) ;;
    esac
    case "$line" in
      "") continue ;;
      # The enumerated store paths under "these N derivations will be built:"
      " "*/nix/store/*) continue ;;
      # Those list headers end in a colon promising the list we just dropped,
      # which reads as truncated output. Restate them as complete sentences.
      "these "*" will be "*: | "this "*" will be "*:)
        case "$line" in
          "these "*) line=${line#these } ;;
          "this "*) line="1 ${line#this }" ;;
        esac
        printf '%s\n' "${line%:}"
        continue
        ;;
      # git's fetch progress, including the indented ref-update line.
      "remote: "* | "From "* | " "*".."*"->"*) continue ;;
      # Per-derivation build output, "<name>> text". The "building '...'"
      # line already marks it and the text is in the transcript. Requiring a
      # space-free prefix stops this eating lines that contain "> ".
      *"> "*)
        prefix=${line%%> *}
        case "$prefix" in
          "" | *[[:space:]]*) ;;
          *) continue ;;
        esac
        ;;
    esac

    # Nix writes its progress in lowercase ("building the system
    # configuration..."), and in the workspace UI those lines sit among
    # sentences from every other log source. Capitalise the first letter --
    # but only when the first word is a plain word, so that program names
    # ("nixos-rebuild: ...") and paths stay exactly as they were written.
    case "${line%% *}" in
      [a-z]*[!a-zA-Z:]*) ;;
      [a-z]*) line="${line^}" ;;
    esac

    printf '%s\n' "$line"
  done
}

# `switch` and `boot` both build before activating, so a configuration that
# fails to build never touches the running system; a separate `nix build`
# gate would add nothing.
#
# No --override-input, no --refresh, no --no-write-lock-file: the flake is a
# local checkout that we fetched explicitly, so the command below is exactly
# what a user can type by hand.
nix_apply() {
  local operation="$1" transcript="$2" rc

  $NIX_SUDO install -d -m 0755 "$NIX_LOG_DIR"
  $NIX_SUDO install -m 0644 /dev/null "$transcript"
  $NIX_SUDO ln -sfn "$transcript" "$NIX_LOG_DIR/rebuild-latest.log"

  # stdbuf so output streams instead of arriving in one burst at the end.
  set +e
  $NIX_SUDO nixos-rebuild "$operation" \
    --flake "$NIX_FLAKE_DIR#$NIX_FLAKE_ATTR" \
    --print-build-logs \
    2>&1 | stdbuf -oL $NIX_SUDO tee -a "$transcript" | nix_filter_log \
    | while IFS= read -r line; do nix_log info "$line"; done
  rc=${PIPESTATUS[0]}
  set -e

  return "$rc"
}

# coder_script does not prevent overlapping cron runs, and two concurrent
# nixos-rebuild processes are a bad time.
nix_lock() {
  local lock="$NIX_STATE_DIR/rebuild.lock"
  $NIX_SUDO install -d -m 0755 "$NIX_STATE_DIR"
  # Mode 0666 so the workspace user can take the same advisory lock as root.
  # It carries no data, only the lock.
  [ -e "$lock" ] || $NIX_SUDO install -m 0666 /dev/null "$lock"
  exec 9> "$lock"
  if [ "${1:-wait}" = "nowait" ]; then
    flock -n 9
  else
    flock 9
  fi
}
