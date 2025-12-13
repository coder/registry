#!/usr/bin/env bash

BOLD='\033[0;1m'
RESET='\033[0m'
MUX_BINARY="${INSTALL_PREFIX}/mux"

function run_mux() {
  # Remove stale server lock if present
  rm -f "$HOME/.mux/server.lock"

  local port_value
  port_value="${PORT}"
  if [ -z "$port_value" ]; then
    port_value="4000"
  fi
  # Build args for mux (POSIX-compatible, avoid bash arrays)
  set -- server --port "$port_value"
  if [ -n "${ADD_PROJECT}" ]; then
    set -- "$@" --add-project "${ADD_PROJECT}"
  fi
  echo "🚀 Starting mux server on port $port_value..."
  echo "Check logs at ${LOG_PATH}!"
  PORT="$port_value" "$MUX_BINARY" "$@" > "${LOG_PATH}" 2>&1 &
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
  printf "$${BOLD}Installing mux from npm...\n"

  # Clean up from other install (in case install prefix changed).
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ -e "$CODER_SCRIPT_BIN_DIR/mux" ]; then
    rm "$CODER_SCRIPT_BIN_DIR/mux"
  fi

  mkdir -p "$(dirname "$MUX_BINARY")"

  if command -v npm > /dev/null 2>&1; then
    echo "📦 Installing mux via npm into ${INSTALL_PREFIX}..."
    NPM_WORKDIR="${INSTALL_PREFIX}/npm"
    mkdir -p "$NPM_WORKDIR"
    cd "$NPM_WORKDIR" || exit 1
    if [ ! -f package.json ]; then
      echo '{}' > package.json
    fi
    echo "⏭️  Skipping npm lifecycle scripts with --ignore-scripts"
    PKG="mux"
    if [ -z "${VERSION}" ] || [ "${VERSION}" = "latest" ]; then
      PKG_SPEC="$PKG@latest"
    else
      PKG_SPEC="$PKG@${VERSION}"
    fi
    if ! npm install --no-audit --no-fund --omit=dev --ignore-scripts "$PKG_SPEC"; then
      echo "❌ Failed to install mux via npm"
      exit 1
    fi
    # Determine the installed binary path
    BIN_DIR="$NPM_WORKDIR/node_modules/.bin"
    CANDIDATE="$BIN_DIR/mux"
    if [ ! -f "$CANDIDATE" ]; then
      echo "❌ Could not locate mux binary after npm install"
      exit 1
    fi
    chmod +x "$CANDIDATE" || true
    ln -sf "$CANDIDATE" "$MUX_BINARY"
  else
    echo "📥 npm not found; downloading tarball from npm registry..."
    VERSION_TO_USE="${VERSION}"
    if [ -z "$VERSION_TO_USE" ]; then
      VERSION_TO_USE="next"
    fi
    META_URL="https://registry.npmjs.org/mux/$VERSION_TO_USE"
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
      TARBALL_URL="$(printf "%s" "$META_ONE_LINE" | sed -n 's/.*\"tarball\":\"\\([^\"]*\\)\".*/\\1/p' | head -n1)"
    fi
    # Fallback: resolve version then construct tarball URL
    if [ -z "$TARBALL_URL" ]; then
      RESOLVED_VERSION=""
      if command -v node > /dev/null 2>&1; then
        RESOLVED_VERSION="$(printf "%s" "$META_JSON" | node -e 'try{const fs=require("fs");const data=JSON.parse(fs.readFileSync(0,"utf8"));if(data&&data.version){console.log(data.version);}}catch(e){}')"
      fi
      if [ -z "$RESOLVED_VERSION" ]; then
        RESOLVED_VERSION="$(printf "%s" "$META_ONE_LINE" | sed -n 's/.*\"version\":\"\\([^\"]*\\)\".*/\\1/p' | head -n1)"
      fi
      if [ -z "$RESOLVED_VERSION" ]; then
        RESOLVED_VERSION="$(printf "%s" "$META_ONE_LINE" | grep -o '\"version\":\"[^\"]*\"' | head -n1 | cut -d '\"' -f4)"
      fi
      if [ -n "$RESOLVED_VERSION" ]; then
        VERSION_TO_USE="$RESOLVED_VERSION"
      fi
      if [ -z "$VERSION_TO_USE" ]; then
        echo "❌ Could not determine version for mux"
        exit 1
      fi
      TARBALL_URL="https://registry.npmjs.org/mux/-/mux-$VERSION_TO_USE.tgz"
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
        BIN_PATH=$(sed -n 's/.*\"bin\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' "$TMP_DIR/package/package.json" | head -n1)
        if [ -z "$BIN_PATH" ]; then
          BIN_PATH=$(sed -n '/\"bin\"[[:space:]]*:[[:space:]]*{/,/}/p' "$TMP_DIR/package/package.json" | sed -n 's/.*\"mux\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n1)
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
