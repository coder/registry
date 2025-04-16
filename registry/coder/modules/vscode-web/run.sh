#!/usr/bin/env bash

BOLD='\033[0;1m'
EXTENSIONS=("${EXTENSIONS}")
VSCODE_WEB="${INSTALL_PREFIX}/bin/code-server"

# Set extension directory
EXTENSION_ARG=""
if [ -n "${EXTENSIONS_DIR}" ]; then
  EXTENSION_ARG="--extensions-dir=${EXTENSIONS_DIR}"
fi

# Set extension directory
SERVER_BASE_PATH_ARG=""
if [ -n "${SERVER_BASE_PATH}" ]; then
  SERVER_BASE_PATH_ARG="--server-base-path=${SERVER_BASE_PATH}"
fi

run_vscode_web() {
  echo "👷 Running $VSCODE_WEB serve-local $EXTENSION_ARG $SERVER_BASE_PATH_ARG --port ${PORT} --host 127.0.0.1 --accept-server-license-terms --without-connection-token --telemetry-level ${TELEMETRY_LEVEL} in the background..."
  echo "Check logs at ${LOG_PATH}!"
  "$VSCODE_WEB" serve-local "$EXTENSION_ARG" "$SERVER_BASE_PATH_ARG" --port "${PORT}" --host 127.0.0.1 --accept-server-license-terms --without-connection-token --telemetry-level "${TELEMETRY_LEVEL}" > "${LOG_PATH}" 2>&1 &
}

# Check if the settings file exists...
if [ ! -f ~/.vscode-server/data/Machine/settings.json ]; then
  echo "⚙️ Creating settings file..."
  mkdir -p ~/.vscode-server/data/Machine
  echo "${SETTINGS}" > ~/.vscode-server/data/Machine/settings.json
fi

# Check if vscode-server is already installed for offline or cached mode
if [ -f "$VSCODE_WEB" ]; then
  if [ "${OFFLINE}" = true ] || [ "${USE_CACHED}" = true ]; then
    echo "🥳 Found a copy of VS Code Web"
    run_vscode_web
    exit 0
  fi
fi
# Offline mode always expects a copy of vscode-server to be present
if [ "${OFFLINE}" = true ]; then
  echo "Failed to find a copy of VS Code Web"
  exit 1
fi

# Create install prefix
mkdir -p ${INSTALL_PREFIX}

printf "$${BOLD}Installing Microsoft Visual Studio Code Server!\n"

# Download and extract vscode-server
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="x64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture"
    exit 1
    ;;
esac

# Check if a specific VS Code Web commit ID was provided
if [ -n "${COMMIT_ID}" ]; then
  HASH="${COMMIT_ID}"
else
  HASH=$(curl -fsSL https://update.code.visualstudio.com/api/commits/stable/server-linux-$ARCH-web | cut -d '"' -f 2)
fi
printf "$${BOLD}VS Code Web commit id version $HASH.\n"

output=$(curl -fsSL "https://vscode.download.prss.microsoft.com/dbazure/download/stable/$HASH/vscode-server-linux-$ARCH-web.tar.gz" | tar -xz -C "${INSTALL_PREFIX}" --strip-components 1)

if [ $? -ne 0 ]; then
  echo "Failed to install Microsoft Visual Studio Code Server: $output"
  exit 1
fi
printf "$${BOLD}VS Code Web has been installed.\n"

# Install each extension...
IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
for extension in "$${EXTENSIONLIST[@]}"; do
  if [ -z "$extension" ]; then
    continue
  fi
  printf "🧩 Installing extension $${CODE}$extension$${RESET}...\n"
  output=$($VSCODE_WEB "$EXTENSION_ARG" --install-extension "$extension" --force)
  if [ $? -ne 0 ]; then
    echo "Failed to install extension: $extension: $output"
  fi
done

if [ "${AUTO_INSTALL_EXTENSIONS}" = true ]; then
  if ! command -v jq > /dev/null; then
    echo "jq is required to install extensions from a workspace file."
  else
    WORKSPACE_DIR="$HOME"
    if [ -n "${FOLDER}" ]; then
      WORKSPACE_DIR="${FOLDER}"
    fi

    if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
      printf "🧩 Installing extensions from %s/.vscode/extensions.json...\n" "$WORKSPACE_DIR"
      # Use sed to remove single-line comments before parsing with jq
      extensions=$(sed 's|//.*||g' "$WORKSPACE_DIR"/.vscode/extensions.json | jq -r '.recommendations[]')
      for extension in $extensions; do
        $VSCODE_WEB "$EXTENSION_ARG" --install-extension "$extension" --force
      done
    fi
  fi
fi

run_vscode_web
