#!/usr/bin/env bash

BOLD='\033[0;1m'
RESET='\033[0m'
CODE='\033[36;40;1m'
EXTENSIONS=("${EXTENSIONS}")

# Set extension directory argument
EXTENSION_ARG=""
if [ -n "${EXTENSIONS_DIR}" ]; then
  EXTENSION_ARG="--extensions-dir=${EXTENSIONS_DIR}"
fi

# Set server base path argument
SERVER_BASE_PATH_ARG=""
if [ -n "${SERVER_BASE_PATH}" ]; then
  SERVER_BASE_PATH_ARG="--server-base-path=${SERVER_BASE_PATH}"
fi

# Set disable workspace trust argument
DISABLE_TRUST_ARG=""
if [ "${DISABLE_TRUST}" = true ]; then
  DISABLE_TRUST_ARG="--disable-workspace-trust"
fi

# Check if code CLI is installed
check_code_cli() {
  if command -v code > /dev/null 2>&1; then
    echo "code"
    return 0
  fi
  if [ -f "${INSTALL_PREFIX}/bin/code" ]; then
    echo "${INSTALL_PREFIX}/bin/code"
    return 0
  fi
  return 1
}

# Check if code-server is installed (fallback option)
check_code_server() {
  if command -v code-server > /dev/null 2>&1; then
    echo "code-server"
    return 0
  fi
  if [ -f "${INSTALL_PREFIX}/bin/code-server" ]; then
    echo "${INSTALL_PREFIX}/bin/code-server"
    return 0
  fi
  return 1
}

# Find existing vscode-server binary (used by code serve-web internally)
find_vscode_server() {
  # Check common locations for pre-downloaded vscode-server
  local server_dirs=(
    "$HOME/.vscode-server/bin"
    "$HOME/.vscode/cli/serve-web"
  )
  for dir in "$${server_dirs[@]}"; do
    if [ -d "$dir" ]; then
      # Find the most recent server version
      local latest
      latest=$(ls -t "$dir" 2> /dev/null | head -1)
      if [ -n "$latest" ] && [ -f "$dir/$latest/bin/code-server" ]; then
        echo "$dir/$latest/bin/code-server"
        return 0
      fi
      if [ -n "$latest" ] && [ -f "$dir/$latest/code-server" ]; then
        echo "$dir/$latest/code-server"
        return 0
      fi
    fi
  done
  return 1
}

# Install VS Code CLI if not present
install_code_cli() {
  printf "$${BOLD}Installing VS Code CLI...$${RESET}\n"

  # Detect architecture
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    armv7l) ARCH="armhf" ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  # Detect platform
  # Note: VS Code CLI uses 'alpine' for all Linux distributions
  PLATFORM=$(uname -s)
  case "$PLATFORM" in
    Linux)
      PLATFORM="alpine"
      ;;
    Darwin)
      PLATFORM="darwin"
      ;;
    *)
      echo "Unsupported platform: $PLATFORM"
      exit 1
      ;;
  esac

  # Create install directory
  mkdir -p "${INSTALL_PREFIX}/bin"

  # Download VS Code CLI
  CLI_URL="https://code.visualstudio.com/sha/download?build=${RELEASE_CHANNEL}&os=cli-$PLATFORM-$ARCH"
  printf "Downloading VS Code CLI from %s\n" "$CLI_URL"

  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$CLI_URL" -o "/tmp/vscode-cli.tar.gz"
  elif command -v wget > /dev/null 2>&1; then
    wget -q "$CLI_URL" -O "/tmp/vscode-cli.tar.gz"
  else
    echo "Neither curl nor wget is available. Please install one of them."
    exit 1
  fi

  # Extract CLI
  tar -xzf /tmp/vscode-cli.tar.gz -C "${INSTALL_PREFIX}/bin"
  rm -f /tmp/vscode-cli.tar.gz

  # The CLI binary is named 'code'
  if [ -f "${INSTALL_PREFIX}/bin/code" ]; then
    chmod +x "${INSTALL_PREFIX}/bin/code"
    export PATH="${INSTALL_PREFIX}/bin:$PATH"
    printf "$${BOLD}VS Code CLI installed successfully.$${RESET}\n"
  else
    echo "Failed to install VS Code CLI"
    exit 1
  fi
}

# Run VS Code Web using the code CLI (serve-web command)
run_vscode_web_cli() {
  local CODE_CMD="$1"

  # Build the command arguments
  ARGS="serve-web --port ${PORT} --host 127.0.0.1 --accept-server-license-terms --without-connection-token --telemetry-level ${TELEMETRY_LEVEL}"

  if [ -n "$EXTENSION_ARG" ]; then
    ARGS="$ARGS $EXTENSION_ARG"
  fi

  if [ -n "$SERVER_BASE_PATH_ARG" ]; then
    ARGS="$ARGS $SERVER_BASE_PATH_ARG"
  fi

  if [ -n "$DISABLE_TRUST_ARG" ]; then
    ARGS="$ARGS $DISABLE_TRUST_ARG"
  fi

  if [ -n "${COMMIT_ID}" ]; then
    ARGS="$ARGS --commit-id ${COMMIT_ID}"
  fi

  printf "Starting VS Code Web on port ${PORT}...\n"
  printf "Check logs at ${LOG_PATH}\n"

  # shellcheck disable=SC2086
  "$CODE_CMD" $ARGS > "${LOG_PATH}" 2>&1 &
}

# Run VS Code Web using code-server (fallback for offline mode)
run_code_server() {
  local SERVER_CMD="$1"

  printf "Starting code-server on port ${PORT}...\n"
  printf "Check logs at ${LOG_PATH}\n"

  # Build arguments for code-server
  ARGS="--port ${PORT} --host 127.0.0.1 --auth none"

  if [ -n "$EXTENSION_ARG" ]; then
    ARGS="$ARGS $EXTENSION_ARG"
  fi

  # shellcheck disable=SC2086
  "$SERVER_CMD" $ARGS > "${LOG_PATH}" 2>&1 &
}

# Run VS Code Web using vscode-server binary directly
run_vscode_server() {
  local SERVER_CMD="$1"

  printf "Starting VS Code Server on port ${PORT}...\n"
  printf "Check logs at ${LOG_PATH}\n"

  # Build arguments for vscode-server
  ARGS="--port ${PORT} --host 127.0.0.1 --without-connection-token --accept-server-license-terms --telemetry-level ${TELEMETRY_LEVEL}"

  if [ -n "$EXTENSION_ARG" ]; then
    ARGS="$ARGS $EXTENSION_ARG"
  fi

  if [ -n "$SERVER_BASE_PATH_ARG" ]; then
    ARGS="$ARGS $SERVER_BASE_PATH_ARG"
  fi

  # shellcheck disable=SC2086
  "$SERVER_CMD" serve-local $ARGS > "${LOG_PATH}" 2>&1 &
}

install_extensions() {
  local CODE_CMD="$1"

  # Install specified extensions
  IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
  for extension in "$${EXTENSIONLIST[@]}"; do
    if [ -z "$extension" ]; then
      continue
    fi
    printf "Installing extension $${CODE}$extension$${RESET}...\n"
    output=$("$CODE_CMD" $EXTENSION_ARG --install-extension "$extension" --force 2>&1)
    if [ $? -ne 0 ]; then
      echo "Failed to install extension: $extension: $output"
    fi
  done

  # Auto-install extensions from workspace or folder
  if [ "${AUTO_INSTALL_EXTENSIONS}" = true ]; then
    if ! command -v jq > /dev/null; then
      echo "jq is required to install extensions from a workspace file."
    else
      if [ -n "${WORKSPACE}" ] && [ -f "${WORKSPACE}" ]; then
        printf "Installing extensions from %s...\n" "${WORKSPACE}"
        extensions=$(sed 's|//.*||g' "${WORKSPACE}" | jq -r '(.extensions.recommendations // [])[]')
        for extension in $extensions; do
          "$CODE_CMD" $EXTENSION_ARG --install-extension "$extension" --force
        done
      else
        WORKSPACE_DIR="$HOME"
        if [ -n "${FOLDER}" ]; then
          WORKSPACE_DIR="${FOLDER}"
        fi
        if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
          printf "Installing extensions from %s/.vscode/extensions.json...\n" "$WORKSPACE_DIR"
          extensions=$(sed 's|//.*||g' "$WORKSPACE_DIR/.vscode/extensions.json" | jq -r '.recommendations[]')
          for extension in $extensions; do
            "$CODE_CMD" $EXTENSION_ARG --install-extension "$extension" --force
          done
        fi
      fi
    fi
  fi
}

# Create settings file if it doesn't exist
if [ ! -f ~/.vscode-server/data/Machine/settings.json ]; then
  printf "Creating settings file...\n"
  mkdir -p ~/.vscode-server/data/Machine
  echo "${SETTINGS}" > ~/.vscode-server/data/Machine/settings.json
fi

# Determine which command to use
CODE_CMD=""
RUN_MODE=""

# Check for code CLI first (preferred)
if CODE_CMD=$(check_code_cli); then
  printf "$${BOLD}Found VS Code CLI at $CODE_CMD$${RESET}\n"
  RUN_MODE="cli"
fi

# Handle offline mode
if [ "${OFFLINE}" = true ]; then
  if [ -n "$CODE_CMD" ]; then
    # Check if vscode-server is already downloaded (code serve-web won't need to download)
    if VSCODE_SERVER=$(find_vscode_server); then
      printf "Found cached VS Code Server at $VSCODE_SERVER\n"
      printf "Using cached VS Code CLI.\n"
      run_vscode_web_cli "$CODE_CMD"
      exit 0
    fi
    # Code CLI exists but vscode-server not cached - try using it anyway
    # (it might work if server was pre-downloaded, or fail gracefully)
    printf "Warning: VS Code Server may not be cached. Attempting to start...\n"
    printf "Using cached VS Code CLI.\n"
    run_vscode_web_cli "$CODE_CMD"
    exit 0
  fi

  # Try code-server as fallback for offline mode
  if SERVER_CMD=$(check_code_server); then
    printf "$${BOLD}Found code-server at $SERVER_CMD (offline fallback)$${RESET}\n"
    run_code_server "$SERVER_CMD"
    exit 0
  fi

  # Try vscode-server binary directly
  if VSCODE_SERVER=$(find_vscode_server); then
    printf "$${BOLD}Found VS Code Server at $VSCODE_SERVER (offline fallback)$${RESET}\n"
    run_vscode_server "$VSCODE_SERVER"
    exit 0
  fi

  echo "Offline mode enabled but no VS Code CLI, code-server, or cached VS Code Server found."
  exit 1
fi

# Handle use_cached mode
if [ "${USE_CACHED}" = true ] && [ -n "$CODE_CMD" ]; then
  printf "Using cached VS Code CLI.\n"
  install_extensions "$CODE_CMD"
  run_vscode_web_cli "$CODE_CMD"
  exit 0
fi

# Install VS Code CLI if not present
if [ -z "$CODE_CMD" ]; then
  install_code_cli
  CODE_CMD="${INSTALL_PREFIX}/bin/code"
  RUN_MODE="cli"
fi

# Install extensions
install_extensions "$CODE_CMD"

# Run VS Code Web
run_vscode_web_cli "$CODE_CMD"
