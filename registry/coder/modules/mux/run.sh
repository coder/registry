#!/usr/bin/env bash

BOLD='\033[0;1m'
RESET='\033[0m'
MUX_BINARY="${INSTALL_PREFIX}/mux"

function run_mux() {
  local port_value
  local auth_token_value
  local restart_on_kill_value
  local restart_delay_seconds_value
  local max_restart_attempts_value

  port_value="${PORT}"
  auth_token_value="${AUTH_TOKEN}"
  restart_on_kill_value="${RESTART_ON_KILL}"
  restart_delay_seconds_value="${RESTART_DELAY_SECONDS}"
  max_restart_attempts_value="${MAX_RESTART_ATTEMPTS}"

  if [ -z "$port_value" ]; then
    port_value="4000"
  fi

  if [ -z "$restart_delay_seconds_value" ]; then
    restart_delay_seconds_value="5"
  fi

  if [ -z "$max_restart_attempts_value" ]; then
    max_restart_attempts_value="0"
  fi

  mkdir -p "$(dirname "${LOG_PATH}")"

  # Build args for mux (POSIX-compatible, avoid bash arrays)
  set -- server --port "$port_value"
  if [ -n "${ADD_PROJECT}" ]; then
    set -- "$@" --add-project "${ADD_PROJECT}"
  fi

  # Parse additional user-supplied server arguments while preserving quoted groups.
  if [ -n "${ADDITIONAL_ARGUMENTS}" ]; then
    local parsed_additional_arguments
    if ! parsed_additional_arguments="$(printf "%s\n" "${ADDITIONAL_ARGUMENTS}" | xargs -n1 printf "%s\n" 2> /dev/null)"; then
      echo "❌ Failed to parse additional_arguments. Ensure quotes are balanced."
      exit 1
    fi
    while IFS= read -r parsed_arg; do
      [ -n "$parsed_arg" ] || continue
      set -- "$@" "$parsed_arg"
    done << EOF_ARGS
$${parsed_additional_arguments}
EOF_ARGS
  fi

  echo "🚀 Starting mux server on port $port_value..."
  echo "Check logs at ${LOG_PATH}!"
  echo "ℹ️ Mux exit details will be appended to ${LOG_PATH} by the launcher."
  if [ "$restart_on_kill_value" = true ]; then
    echo "ℹ️ Auto-restart after mux exits is enabled with a $${restart_delay_seconds_value}-second delay."
    if [ "$max_restart_attempts_value" = "0" ]; then
      echo "ℹ️ Automatic restarts are unlimited for every mux exit."
    else
      echo "ℹ️ Mux will stop restarting after $${max_restart_attempts_value} restart attempts."
    fi
  fi

  nohup env \
    LOG_PATH="${LOG_PATH}" \
    MUX_BINARY="$MUX_BINARY" \
    AUTH_TOKEN="$auth_token_value" \
    PORT_VALUE="$port_value" \
    RESTART_ON_KILL_VALUE="$restart_on_kill_value" \
    RESTART_DELAY_SECONDS_VALUE="$restart_delay_seconds_value" \
    MAX_RESTART_ATTEMPTS_VALUE="$max_restart_attempts_value" \
    bash -s -- "$@" > /dev/null 2>&1 << 'EOF_LAUNCHER' &
signal_name() {
  local signal_number="$1"
  local resolved_signal

  resolved_signal="$(kill -l "$signal_number" 2> /dev/null || true)"
  if [ -n "$resolved_signal" ]; then
    printf '%s' "$resolved_signal"
    return 0
  fi

  printf 'SIG%s' "$signal_number"
}

append_kernel_kill_context() {
  local mux_pid="$1"
  local kernel_context=""

  if command -v dmesg > /dev/null 2>&1; then
    kernel_context="$(dmesg -T 2> /dev/null | grep -Ei "Killed process $mux_pid|out of memory|oom-killer|oom reaper" | tail -n 10 || true)"
  fi

  if [ -z "$kernel_context" ] && command -v journalctl > /dev/null 2>&1; then
    kernel_context="$(journalctl -k -n 200 --no-pager 2> /dev/null | grep -Ei "Killed process $mux_pid|out of memory|oom-killer|oom reaper" | tail -n 10 || true)"
  fi

  if [ -n "$kernel_context" ]; then
    echo "Recent kernel kill context:"
    echo "$kernel_context"
  else
    echo "No kernel OOM/kill context was available (dmesg/journalctl unavailable or permission denied)."
  fi
}

cleanup_mux_lock() {
  rm -f "$HOME/.mux/server.lock"
}

should_restart_mux() {
  [ "$RESTART_ON_KILL_VALUE" = "true" ]
}

log_mux_exit() {
  local mux_pid="$1"
  local exit_code="$2"
  local timestamp

  timestamp="$(date -Iseconds 2> /dev/null || date)"

  if [ "$exit_code" -eq 0 ]; then
    echo "[$timestamp] mux server exited cleanly."
    return 0
  fi

  if [ "$exit_code" -gt 128 ]; then
    local signal_number=$((exit_code - 128))
    local signal_label

    signal_label="$(signal_name "$signal_number")"
    echo "[$timestamp] mux server exited due to signal $signal_label ($signal_number); shell exit code $exit_code."

    if [ "$signal_number" -eq 9 ]; then
      echo "[$timestamp] SIGKILL usually means the process was killed externally or by the OOM killer."
      append_kernel_kill_context "$mux_pid"
    fi

    echo "[$timestamp] Check the earlier mux log lines for any in-process crash breadcrumbs from mux itself."
    return 0
  fi

  echo "[$timestamp] mux server exited with code $exit_code."
  echo "[$timestamp] Check the earlier mux log lines for any in-process crash breadcrumbs from mux itself."
}

log_mux_restart_wait() {
  local timestamp

  timestamp="$(date -Iseconds 2> /dev/null || date)"
  echo "[$timestamp] Waiting $${RESTART_DELAY_SECONDS_VALUE} seconds before restarting mux after it exited."
}

log_mux_restart_cleanup() {
  local timestamp

  timestamp="$(date -Iseconds 2> /dev/null || date)"
  echo "[$timestamp] Removing $HOME/.mux/server.lock before restarting mux."
}

log_mux_restart_cap_reached() {
  local timestamp

  timestamp="$(date -Iseconds 2> /dev/null || date)"
  echo "[$timestamp] Reached the max restart attempts limit ($MAX_RESTART_ATTEMPTS_VALUE); not restarting mux again."
}

restart_attempt_count=0
while true; do
  cleanup_mux_lock
  MUX_SERVER_AUTH_TOKEN="$AUTH_TOKEN" PORT="$PORT_VALUE" "$MUX_BINARY" "$@" >> "$LOG_PATH" 2>&1 &
  mux_pid=$!
  wait "$mux_pid"
  exit_code=$?
  log_mux_exit "$mux_pid" "$exit_code" >> "$LOG_PATH" 2>&1

  if should_restart_mux; then
    if [ "$MAX_RESTART_ATTEMPTS_VALUE" -gt 0 ] && [ "$restart_attempt_count" -ge "$MAX_RESTART_ATTEMPTS_VALUE" ]; then
      log_mux_restart_cap_reached >> "$LOG_PATH" 2>&1
      break
    fi

    restart_attempt_count=$((restart_attempt_count + 1))
    log_mux_restart_wait >> "$LOG_PATH" 2>&1
    sleep "$RESTART_DELAY_SECONDS_VALUE"
    cleanup_mux_lock
    log_mux_restart_cleanup >> "$LOG_PATH" 2>&1
    continue
  fi

  break
done
EOF_LAUNCHER
}
# Check if mux is already installed for offline mode
if [ "${OFFLINE}" = true ]; then
  if [ -f "$MUX_BINARY" ]; then
    echo "🥳 Found a copy of mux"
    run_mux
    exit 0
  fi
  echo "❌ Failed to find a copy of mux"
  exit 1
fi

# If there is no cached install OR we don't want to use a cached install
if [ ! -f "$MUX_BINARY" ] || [ "${USE_CACHED}" != true ]; then
  printf "$${BOLD}Installing mux...\n"

  # Clean up from other install (in case install prefix changed).
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ -e "$CODER_SCRIPT_BIN_DIR/mux" ]; then
    rm "$CODER_SCRIPT_BIN_DIR/mux"
  fi

  mkdir -p "$(dirname "$MUX_BINARY")"

  # Determine which package manager to use
  PM_CMD=""
  if [ "${PACKAGE_MANAGER}" = "auto" ]; then
    for pm in npm pnpm bun; do
      if command -v "$pm" > /dev/null 2>&1; then
        PM_CMD="$pm"
        break
      fi
    done
  else
    PM_CMD="${PACKAGE_MANAGER}"
    if ! command -v "$PM_CMD" > /dev/null 2>&1; then
      echo "❌ Configured package manager '${PACKAGE_MANAGER}' not found on PATH"
      exit 1
    fi
  fi

  if [ -n "$PM_CMD" ]; then
    echo "📦 Installing mux via $PM_CMD into ${INSTALL_PREFIX}..."
    NPM_WORKDIR="${INSTALL_PREFIX}/npm"
    mkdir -p "$NPM_WORKDIR"
    cd "$NPM_WORKDIR" || exit 1
    if [ ! -f package.json ]; then
      echo '{}' > package.json
    fi
    echo "⏭️  Skipping lifecycle scripts with --ignore-scripts"
    PKG="mux"
    if [ -z "${VERSION}" ] || [ "${VERSION}" = "latest" ]; then
      PKG_SPEC="$PKG@latest"
    else
      PKG_SPEC="$PKG@${VERSION}"
    fi
    INSTALL_OK=true
    case "$PM_CMD" in
      npm)
        if ! npm install --no-audit --no-fund --omit=dev --ignore-scripts --registry "${REGISTRY_URL}" "$PKG_SPEC"; then
          INSTALL_OK=false
        fi
        ;;
      pnpm)
        if ! pnpm add --ignore-scripts --registry "${REGISTRY_URL}" "$PKG_SPEC"; then
          INSTALL_OK=false
        fi
        ;;
      bun)
        if ! bun add --ignore-scripts --registry "${REGISTRY_URL}" "$PKG_SPEC"; then
          INSTALL_OK=false
        fi
        ;;
    esac
    if [ "$INSTALL_OK" != true ]; then
      echo "❌ Failed to install mux via $PM_CMD"
      exit 1
    fi
    # Determine the installed binary path
    BIN_DIR="$NPM_WORKDIR/node_modules/.bin"
    CANDIDATE="$BIN_DIR/mux"
    if [ ! -f "$CANDIDATE" ]; then
      echo "❌ Could not locate mux binary after $PM_CMD install"
      exit 1
    fi
    chmod +x "$CANDIDATE" || true
    ln -sf "$CANDIDATE" "$MUX_BINARY"
  else
    echo "📥 No package manager found; downloading tarball from registry..."
    VERSION_TO_USE="${VERSION}"
    if [ -z "$VERSION_TO_USE" ]; then
      VERSION_TO_USE="next"
    fi
    META_URL="${REGISTRY_URL}/mux/$VERSION_TO_USE"
    META_JSON="$(curl -fsSL "$META_URL" || true)"
    if [ -z "$META_JSON" ]; then
      echo "❌ Failed to fetch npm metadata: $META_URL"
      exit 1
    fi
    # Normalize JSON to a single line for robust pattern matching across environments
    META_ONE_LINE="$(printf "%s" "$META_JSON" | tr -d '\n' || true)"
    if [ -z "$META_ONE_LINE" ]; then
      META_ONE_LINE="$META_JSON"
    fi
    # Try to extract tarball URL directly from metadata (prefer Node if available for robust JSON parsing)
    TARBALL_URL=""
    if command -v node > /dev/null 2>&1; then
      TARBALL_URL="$(printf "%s" "$META_JSON" | node -e 'try{const fs=require("fs");const data=JSON.parse(fs.readFileSync(0,"utf8"));if(data&&data.dist&&data.dist.tarball){console.log(data.dist.tarball);}}catch(e){}')"
    fi
    # sed-based fallback
    if [ -z "$TARBALL_URL" ]; then
      TARBALL_URL="$(printf "%s" "$META_ONE_LINE" | sed -n 's/.*"tarball":"\([^"]*\)".*/\1/p' | head -n1)"
    fi
    # Fallback: resolve version then construct tarball URL
    if [ -z "$TARBALL_URL" ]; then
      RESOLVED_VERSION=""
      if command -v node > /dev/null 2>&1; then
        RESOLVED_VERSION="$(printf "%s" "$META_JSON" | node -e 'try{const fs=require("fs");const data=JSON.parse(fs.readFileSync(0,"utf8"));if(data&&data.version){console.log(data.version);}}catch(e){}')"
      fi
      if [ -z "$RESOLVED_VERSION" ]; then
        RESOLVED_VERSION="$(printf "%s" "$META_ONE_LINE" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1)"
      fi
      if [ -z "$RESOLVED_VERSION" ]; then
        RESOLVED_VERSION="$(printf "%s" "$META_ONE_LINE" | grep -o '"version":"[^"]*"' | head -n1 | cut -d '"' -f4)"
      fi
      if [ -n "$RESOLVED_VERSION" ]; then
        VERSION_TO_USE="$RESOLVED_VERSION"
      fi
      if [ -z "$VERSION_TO_USE" ]; then
        echo "❌ Could not determine version for mux"
        exit 1
      fi
      TARBALL_URL="${REGISTRY_URL}/mux/-/mux-$VERSION_TO_USE.tgz"
    fi
    TMP_DIR="$(mktemp -d)"
    TAR_PATH="$TMP_DIR/mux.tgz"
    if ! curl -fsSL "$TARBALL_URL" -o "$TAR_PATH"; then
      echo "❌ Failed to download tarball: $TARBALL_URL"
      rm -rf "$TMP_DIR"
      exit 1
    fi
    if ! tar -xzf "$TAR_PATH" -C "$TMP_DIR"; then
      echo "❌ Failed to extract tarball"
      rm -rf "$TMP_DIR"
      exit 1
    fi
    CANDIDATE=""
    BIN_PATH=""
    # Prefer reading bin path from package.json
    if [ -f "$TMP_DIR/package/package.json" ]; then
      if command -v node > /dev/null 2>&1; then
        BIN_PATH="$(node -e 'try{const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));let bp=typeof p.bin==="string"?p.bin:(p.bin&&p.bin.mux);if(bp){console.log(bp)}}catch(e){}' "$TMP_DIR/package/package.json")"
      fi
      if [ -z "$BIN_PATH" ]; then
        # sed fallbacks (handle both string and object forms)
        BIN_PATH=$(sed -n 's/.*"bin"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_DIR/package/package.json" | head -n1)
        if [ -z "$BIN_PATH" ]; then
          BIN_PATH=$(sed -n '/"bin"[[:space:]]*:[[:space:]]*{/,/}/p' "$TMP_DIR/package/package.json" | sed -n 's/.*"mux"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
        fi
      fi
      if [ -n "$BIN_PATH" ] && [ -f "$TMP_DIR/package/$BIN_PATH" ]; then
        CANDIDATE="$TMP_DIR/package/$BIN_PATH"
      fi
    fi
    # Fallback: check common locations
    if [ -z "$CANDIDATE" ]; then
      if [ -f "$TMP_DIR/package/bin/mux" ]; then
        CANDIDATE="$TMP_DIR/package/bin/mux"
      elif [ -f "$TMP_DIR/package/bin/mux.js" ]; then
        CANDIDATE="$TMP_DIR/package/bin/mux.js"
      elif [ -f "$TMP_DIR/package/bin/mux.mjs" ]; then
        CANDIDATE="$TMP_DIR/package/bin/mux.mjs"
      fi
    fi
    # Fallback: search for plausible filenames
    if [ -z "$CANDIDATE" ] || [ ! -f "$CANDIDATE" ]; then
      CANDIDATE=$(find "$TMP_DIR/package" -maxdepth 4 -type f \( -name "mux" -o -name "mux.js" -o -name "mux.mjs" -o -name "mux.cjs" -o -name "main.js" \) | head -n1)
    fi
    if [ -z "$CANDIDATE" ] || [ ! -f "$CANDIDATE" ]; then
      echo "❌ Could not locate mux binary in tarball"
      rm -rf "$TMP_DIR"
      exit 1
    fi
    # Copy entire package to installation directory to preserve relative imports
    DEST_DIR="${INSTALL_PREFIX}/.mux-package"
    rm -rf "$DEST_DIR"
    mkdir -p "$DEST_DIR"
    cp -R "$TMP_DIR/package/." "$DEST_DIR/"
    # Create/refresh launcher symlink
    if [ -n "$BIN_PATH" ] && [ -f "$DEST_DIR/$BIN_PATH" ]; then
      ln -sf "$DEST_DIR/$BIN_PATH" "$MUX_BINARY"
      chmod +x "$DEST_DIR/$BIN_PATH" || true
    else
      ln -sf "$DEST_DIR/$(basename "$CANDIDATE")" "$MUX_BINARY"
      chmod +x "$DEST_DIR/$(basename "$CANDIDATE")" || true
    fi
    rm -rf "$TMP_DIR"
  fi

  printf "🥳 mux has been installed in ${INSTALL_PREFIX}\n\n"
fi

# Make mux available in PATH if CODER_SCRIPT_BIN_DIR is set
if [ -n "$CODER_SCRIPT_BIN_DIR" ]; then
  if [ ! -e "$CODER_SCRIPT_BIN_DIR/mux" ]; then
    ln -s "$MUX_BINARY" "$CODER_SCRIPT_BIN_DIR/mux"
  fi
fi

# Start mux
run_mux
