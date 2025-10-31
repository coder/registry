#!/usr/bin/env bash

BOLD='\033[0;1m'
RESET='\033[0m'
CMUX_BINARY="${INSTALL_PREFIX}/cmux"

function run_cmux() {
  local port_value
  port_value="${PORT}"
  if [ -z "$port_value" ]; then
    port_value="4000"
  fi
  echo "🚀 Starting cmux server on port $port_value..."
  echo "Check logs at ${LOG_PATH}!"
  PORT="$port_value" "$CMUX_BINARY" server --port "$port_value" > "${LOG_PATH}" 2>&1 &
}

# Check if cmux is already installed for offline mode
if [ "${OFFLINE}" = true ]; then
  if [ -f "$CMUX_BINARY" ]; then
    echo "🥳 Found a copy of cmux"
    run_cmux
    exit 0
  fi
  echo "❌ Failed to find a copy of cmux"
  exit 1
fi

# If there is no cached install OR we don't want to use a cached install
if [ ! -f "$CMUX_BINARY" ] || [ "${USE_CACHED}" != true ]; then
  printf "$${BOLD}Installing cmux from npm...\n"

  # Clean up from other install (in case install prefix changed).
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ -e "$CODER_SCRIPT_BIN_DIR/cmux" ]; then
    rm "$CODER_SCRIPT_BIN_DIR/cmux"
  fi

  mkdir -p "$(dirname "$CMUX_BINARY")"

  if command -v npm > /dev/null 2>&1; then
    echo "📦 Installing @coder/cmux via npm into ${INSTALL_PREFIX}..."
    NPM_WORKDIR="${INSTALL_PREFIX}/npm"
    mkdir -p "$NPM_WORKDIR"
    cd "$NPM_WORKDIR" || exit 1
    if [ ! -f package.json ]; then
      echo '{}' > package.json
    fi
    PKG="@coder/cmux"
    if [ -z "${VERSION}" ] || [ "${VERSION}" = "latest" ]; then
      PKG_SPEC="$PKG@latest"
    else
      PKG_SPEC="$PKG@${VERSION}"
    fi
    if ! npm install --no-audit --no-fund --omit=dev "$PKG_SPEC"; then
      echo "❌ Failed to install @coder/cmux via npm"
      exit 1
    fi
    # Determine the installed binary path
    BIN_DIR="$NPM_WORKDIR/node_modules/.bin"
    CANDIDATE="$BIN_DIR/cmux"
    if [ ! -f "$CANDIDATE" ]; then
      echo "❌ Could not locate cmux binary after npm install"
      exit 1
    fi
    chmod +x "$CANDIDATE" || true
    ln -sf "$CANDIDATE" "$CMUX_BINARY"
  else
    echo "📥 npm not found; downloading tarball from npm registry..."
    VERSION_TO_USE="${VERSION}"
    if [ -z "$VERSION_TO_USE" ] || [ "$VERSION_TO_USE" = "latest" ]; then
      # Try to determine the latest version
      META_URL="https://registry.npmjs.org/@coder/cmux/latest"
      VERSION_TO_USE="$(curl -fsSL "$META_URL" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1)"
      if [ -z "$VERSION_TO_USE" ]; then
        echo "❌ Could not determine latest version for @coder/cmux"
        exit 1
      fi
    fi
    TARBALL_URL="https://registry.npmjs.org/@coder/cmux/-/cmux-$${VERSION_TO_USE}.tgz"
    TMP_DIR="$(mktemp -d)"
    TAR_PATH="$TMP_DIR/cmux.tgz"
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
    if [ -f "$TMP_DIR/package/bin/cmux" ]; then
      CANDIDATE="$TMP_DIR/package/bin/cmux"
    else
      CANDIDATE="$(find "$TMP_DIR/package" -maxdepth 3 -type f -name "cmux" | head -n1)"
    fi
    if [ -z "$CANDIDATE" ] || [ ! -f "$CANDIDATE" ]; then
      echo "❌ Could not locate cmux binary in tarball"
      rm -rf "$TMP_DIR"
      exit 1
    fi
    cp "$CANDIDATE" "$CMUX_BINARY"
    chmod +x "$CMUX_BINARY" || true
    rm -rf "$TMP_DIR"
  fi

  printf "🥳 cmux has been installed in ${INSTALL_PREFIX}\n\n"
fi

# Make cmux available in PATH if CODER_SCRIPT_BIN_DIR is set
if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/cmux" ]; then
  ln -s "$CMUX_BINARY" "$CODER_SCRIPT_BIN_DIR/cmux"
fi

# Start cmux
run_cmux
