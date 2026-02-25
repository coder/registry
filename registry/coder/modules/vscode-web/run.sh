#!/usr/bin/env bash

BOLD='\033[0;1m'
EXTENSIONS=("${EXTENSIONS}")
VSCODE_WEB="${INSTALL_PREFIX}/bin/code-server"

# Merge settings from module with existing settings file
# Uses jq if available, falls back to Python3 for deep merge
merge_settings() {
  local new_settings="$1"
  local settings_file="$2"

  if [ -z "$new_settings" ] || [ "$new_settings" = "{}" ]; then
    return 0
  fi

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    printf '%s\n' "$new_settings" > "$settings_file"
    printf "⚙️ Creating settings file...\n"
    return 0
  fi

  local tmpfile
  tmpfile="$(mktemp)"

  if command -v jq > /dev/null 2>&1; then
    if jq -s '.[0] * .[1]' "$settings_file" <(printf '%s\n' "$new_settings") > "$tmpfile" 2> /dev/null; then
      mv "$tmpfile" "$settings_file"
      printf "⚙️ Merging settings...\n"
      return 0
    fi
  fi

  if command -v python3 > /dev/null 2>&1; then
    if python3 -c "import json,sys;m=lambda a,b:{**a,**{k:m(a[k],v)if k in a and type(a[k])==type(v)==dict else v for k,v in b.items()}};print(json.dumps(m(json.load(open(sys.argv[1])),json.loads(sys.argv[2])),indent=2))" "$settings_file" "$new_settings" > "$tmpfile" 2> /dev/null; then
      mv "$tmpfile" "$settings_file"
      printf "⚙️ Merging settings...\n"
      return 0
    fi
  fi

  rm -f "$tmpfile"
  printf "Warning: Could not merge settings (jq or python3 required). Keeping existing settings.\n"
  return 0
}

# Set extension directory
EXTENSION_ARG=""
if [ -n "${EXTENSIONS_DIR}" ]; then
  EXTENSION_ARG="--extensions-dir=${EXTENSIONS_DIR}"
fi

# Set server base path
SERVER_BASE_PATH_ARG=""
if [ -n "${SERVER_BASE_PATH}" ]; then
  SERVER_BASE_PATH_ARG="--server-base-path=${SERVER_BASE_PATH}"
fi

# Set disable workspace trust
DISABLE_TRUST_ARG=""
if [ "${DISABLE_TRUST}" = true ]; then
  DISABLE_TRUST_ARG="--disable-workspace-trust"
fi

run_vscode_web() {
  echo "👷 Running $VSCODE_WEB serve-local $EXTENSION_ARG $SERVER_BASE_PATH_ARG $DISABLE_TRUST_ARG --port ${PORT} --host 127.0.0.1 --accept-server-license-terms --without-connection-token --telemetry-level ${TELEMETRY_LEVEL} in the background..."
  echo "Check logs at ${LOG_PATH}!"
  "$VSCODE_WEB" serve-local "$EXTENSION_ARG" "$SERVER_BASE_PATH_ARG" "$DISABLE_TRUST_ARG" --port "${PORT}" --host 127.0.0.1 --accept-server-license-terms --without-connection-token --telemetry-level "${TELEMETRY_LEVEL}" > "${LOG_PATH}" 2>&1 &
}

# Apply machine settings (merge with existing if present)
SETTINGS_B64='${SETTINGS_B64}'
if [ -n "$SETTINGS_B64" ]; then
  SETTINGS_JSON="$(echo -n "$SETTINGS_B64" | base64 -d)"
  merge_settings "$SETTINGS_JSON" ~/.vscode-server/data/Machine/settings.json
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

# Detect the platform
if [ -n "${PLATFORM}" ]; then
  DETECTED_PLATFORM="${PLATFORM}"
elif [ -f /etc/alpine-release ] || grep -qi 'ID=alpine' /etc/os-release 2> /dev/null || command -v apk > /dev/null 2>&1; then
  DETECTED_PLATFORM="alpine"
elif [ "$(uname -s)" = "Darwin" ]; then
  DETECTED_PLATFORM="darwin"
else
  DETECTED_PLATFORM="linux"
fi

# Check if a specific VS Code Web commit ID was provided
if [ -n "${COMMIT_ID}" ]; then
  HASH="${COMMIT_ID}"
else
  HASH=$(curl -fsSL https://update.code.visualstudio.com/api/commits/stable/server-$DETECTED_PLATFORM-$ARCH-web | cut -d '"' -f 2)
fi
printf "$${BOLD}VS Code Web commit id version $HASH.\n"

output=$(curl -fsSL "https://vscode.download.prss.microsoft.com/dbazure/download/stable/$HASH/vscode-server-$DETECTED_PLATFORM-$ARCH-web.tar.gz" | tar -xz -C "${INSTALL_PREFIX}" --strip-components 1)

if [ $? -ne 0 ]; then
  echo "Failed to install Microsoft Visual Studio Code Server: $output"
  exit 1
fi
printf "$${BOLD}VS Code Web has been installed.\n"

# Install each extension...
IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
# shellcheck disable=SC2066
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
    # Prefer WORKSPACE if set and points to a file
    if [ -n "${WORKSPACE}" ] && [ -f "${WORKSPACE}" ]; then
      printf "🧩 Installing extensions from %s...\n" "${WORKSPACE}"
      # Strip single-line comments then parse .extensions.recommendations[]
      extensions=$(sed 's|//.*||g' "${WORKSPACE}" | jq -r '(.extensions.recommendations // [])[]')
      for extension in $extensions; do
        $VSCODE_WEB "$EXTENSION_ARG" --install-extension "$extension" --force
      done
    else
      # Fallback to folder-based .vscode/extensions.json (existing behavior)
      WORKSPACE_DIR="$HOME"
      if [ -n "${FOLDER}" ]; then
        WORKSPACE_DIR="${FOLDER}"
      fi
      if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
        printf "🧩 Installing extensions from %s/.vscode/extensions.json...\n" "$WORKSPACE_DIR"
        extensions=$(sed 's|//.*||g' "$WORKSPACE_DIR/.vscode/extensions.json" | jq -r '.recommendations[]')
        for extension in $extensions; do
          $VSCODE_WEB "$EXTENSION_ARG" --install-extension "$extension" --force
        done
      fi
    fi
  fi
fi

run_vscode_web
