#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'

EXTENSIONS="${EXTENSIONS}"
SETTINGS_B64='${SETTINGS_B64}'
CUSTOM_EXTENSIONS_DIR="${EXTENSIONS_DIR}"

# Default paths for VS Code Remote Development
VSCODE_SERVER_DIR="$HOME/.vscode-server"
SETTINGS_FILE="$VSCODE_SERVER_DIR/data/Machine/settings.json"
EXTENSIONS_TARGET="$${CUSTOM_EXTENSIONS_DIR:-$VSCODE_SERVER_DIR/extensions}"

# Merge settings from module with existing settings file.
# Uses jq if available, falls back to python3 for deep merge.
merge_settings() {
  local new_settings="$1"
  local settings_file="$2"

  if [ -z "$new_settings" ] || [ "$new_settings" = "{}" ]; then
    return 0
  fi

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    printf '%s\n' "$new_settings" > "$settings_file"
    printf "⚙️ Created machine settings.\n"
    return 0
  fi

  local tmpfile
  tmpfile="$(mktemp)"

  if command -v jq > /dev/null 2>&1; then
    if jq -s '.[0] * .[1]' "$settings_file" <(printf '%s\n' "$new_settings") > "$tmpfile" 2> /dev/null; then
      mv "$tmpfile" "$settings_file"
      printf "⚙️ Merged machine settings.\n"
      return 0
    fi
  fi

  if command -v python3 > /dev/null 2>&1; then
    if python3 -c "
import json, sys
def merge(a, b):
    r = {**a}
    for k, v in b.items():
        if k in r and isinstance(r[k], dict) and isinstance(v, dict):
            r[k] = merge(r[k], v)
        else:
            r[k] = v
    return r
print(json.dumps(merge(json.load(open(sys.argv[1])), json.loads(sys.argv[2])), indent=2))
" "$settings_file" "$new_settings" > "$tmpfile" 2> /dev/null; then
      mv "$tmpfile" "$settings_file"
      printf "⚙️ Merged machine settings.\n"
      return 0
    fi
  fi

  rm -f "$tmpfile"
  # Fallback: overwrite
  printf '%s\n' "$new_settings" > "$settings_file"
  printf "⚙️ Applied machine settings (overwrite, no merge tool found).\n"
}

# Apply machine settings
if [ -n "$SETTINGS_B64" ]; then
  SETTINGS_JSON=$(echo -n "$SETTINGS_B64" | base64 -d 2>/dev/null) || true
  if [ -n "$${SETTINGS_JSON:-}" ]; then
    merge_settings "$SETTINGS_JSON" "$SETTINGS_FILE"
  fi
fi

# Exit early if no extensions to install
if [ -z "$EXTENSIONS" ]; then
  exit 0
fi

# Find a usable VS Code CLI for extension installation
find_vscode_cli() {
  # 1. Check for existing VS Code Server from a previous Desktop connection
  for f in "$HOME"/.vscode-server/bin/*/bin/remote-cli/code; do
    if [ -x "$f" 2>/dev/null ]; then
      echo "$f"
      return 0
    fi
  done

  # 2. Check for VS Code Web installation (from vscode-web module)
  local web_cli="/tmp/vscode-web/bin/code-server"
  if [ -x "$web_cli" ]; then
    echo "$web_cli"
    return 0
  fi

  return 1
}

VSCODE_CLI=""
if VSCODE_CLI=$(find_vscode_cli); then
  printf "🔍 Found existing VS Code CLI.\n"
else
  # Download VS Code Server for extension installation
  printf "$${BOLD}📦 Downloading VS Code Server for extension installation...$${RESET}\n"

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64) ARCH="arm64" ;;
    *)
      printf "⚠️ Unsupported architecture: %s. Skipping extension installation.\n" "$ARCH"
      exit 0
      ;;
  esac

  PLATFORM="linux"
  if [ -f /etc/alpine-release ] || grep -qi 'ID=alpine' /etc/os-release 2>/dev/null; then
    PLATFORM="alpine"
  fi

  INSTALL_DIR="/tmp/vscode-desktop-ext-installer"
  mkdir -p "$INSTALL_DIR"

  HASH=$(curl -fsSL "https://update.code.visualstudio.com/api/commits/stable/server-$PLATFORM-$ARCH-web" | cut -d '"' -f 2)
  if ! curl -fsSL "https://vscode.download.prss.microsoft.com/dbazure/download/stable/$HASH/vscode-server-$PLATFORM-$ARCH-web.tar.gz" | tar -xz -C "$INSTALL_DIR" --strip-components 1; then
    printf "⚠️ Failed to download VS Code Server. Skipping extension installation.\n"
    exit 0
  fi

  VSCODE_CLI="$INSTALL_DIR/bin/code-server"
  printf "📦 VS Code Server ready.\n"
fi

# Set extensions directory argument
EXTENSION_ARG=""
if [ -n "$CUSTOM_EXTENSIONS_DIR" ]; then
  EXTENSION_ARG="--extensions-dir=$CUSTOM_EXTENSIONS_DIR"
  mkdir -p "$CUSTOM_EXTENSIONS_DIR"
else
  mkdir -p "$EXTENSIONS_TARGET"
fi

# Install each extension
IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
for extension in "$${EXTENSIONLIST[@]}"; do
  if [ -z "$extension" ]; then
    continue
  fi
  printf "🧩 Installing extension $${CODE}%s$${RESET}...\n" "$extension"
  if ! output=$("$VSCODE_CLI" $EXTENSION_ARG --install-extension "$extension" --force 2>&1); then
    printf "⚠️ Warning: could not install %s: %s\n" "$extension" "$output"
  fi
done

printf "✅ Extension installation complete.\n"
