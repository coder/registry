# Ensure a Node.js runtime is available (shux is a Node application launched
# via "#!/usr/bin/env node"). When the workspace image does not provide node,
# bootstrap a pinned runtime into the module data directory so it persists
# across workspace restarts.
#
# This snippet is inserted verbatim into both install.sh and start.sh: they run
# as separate coder_script processes, so a PATH exported by one is not visible
# to the other.
ensure_node() {
  if command -v node > /dev/null 2>&1; then
    return 0
  fi

  local node_version node_arch node_dir
  node_version="${SHUX_NODE_VERSION:-22.14.0}"
  case "$(uname -m)" in
    x86_64 | amd64) node_arch="x64" ;;
    aarch64 | arm64) node_arch="arm64" ;;
    *)
      echo "❌ node is required to run shux but was not found on PATH, and automatic bootstrap does not support architecture '$(uname -m)'."
      exit 1
      ;;
  esac

  node_dir="$HOME/.coder-modules/coder/shux/node/node-v$node_version-linux-$node_arch"
  if [ ! -x "$node_dir/bin/node" ]; then
    echo "⚠️ node not found on PATH; bootstrapping Node.js v$node_version into $node_dir..."
    mkdir -p "$(dirname "$node_dir")"
    if ! curl -fsSL "https://nodejs.org/dist/v$node_version/node-v$node_version-linux-$node_arch.tar.gz" | tar -xz -C "$(dirname "$node_dir")"; then
      echo "❌ Failed to download Node.js v$node_version. shux cannot start without node."
      exit 1
    fi
  fi

  export PATH="$node_dir/bin:$PATH"

  # Expose node to other workspace scripts via the agent bin dir.
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/node" ]; then
    ln -s "$node_dir/bin/node" "$CODER_SCRIPT_BIN_DIR/node"
  fi
}
