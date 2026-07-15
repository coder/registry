#!/usr/bin/env bash

# Enable debug mode dynamically if the flag is true
if [ "${DEBUG}" = true ]; then
  set -x
fi

EXTENSIONS=("${EXTENSIONS}")
BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'
CODE_SERVER="${INSTALL_PREFIX}/bin/code-server"

# Set extension directory
EXTENSION_ARG=""
if [ -n "${EXTENSIONS_DIR}" ]; then
  EXTENSION_ARG="--extensions-dir=${EXTENSIONS_DIR}"
  mkdir -p "${EXTENSIONS_DIR}"
fi

function run_code_server() {
  echo "👷 Running code-server in the background..."
  echo "Check logs at ${LOG_PATH}!"
  $CODE_SERVER "$EXTENSION_ARG" --auth none --port "${PORT}" --app-name "${APP_NAME}" ${ADDITIONAL_ARGS} > "${LOG_PATH}" 2>&1 &
}

# Merge, validate, save, and format settings.json
save_settings() {
  local new_settings="$1"
  local settings_file="$2"
  local overwrite="$3"

  if [ -z "$new_settings" ] || [ "$new_settings" = "{}" ]; then
    return 0
  fi

  local tool=""
  if command -v jq > /dev/null 2>&1; then
    tool="jq"
  elif command -v python3 > /dev/null 2>&1; then
    tool="python3"
  fi

  mkdir -p "$(dirname "$settings_file")"
  local tmpfile
  tmpfile="$(mktemp)"

  # Create or Replace settings.json
  if [ ! -f "$settings_file" ] || [ "$overwrite" = "true" ]; then
    if [ "$tool" = "jq" ]; then
      jq . <(printf '%s' "$new_settings") > "$tmpfile" 2> /dev/null || printf '%s\n' "$new_settings" > "$tmpfile"
    elif [ "$tool" = "python3" ]; then
      python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1]), indent=2))" "$new_settings" > "$tmpfile" 2> /dev/null || printf '%s\n' "$new_settings" > "$tmpfile"
    else
      printf '%s\n' "$new_settings" > "$tmpfile"
    fi
    mv "$tmpfile" "$settings_file"
    printf "⚙️ Creating or replacing settings file...\n"
    return 0
  fi

  # Check if required tooling exists to facilitate the merge
  if [ -z "$tool" ]; then
    rm -f "$tmpfile"
    printf "Warning: Could not merge settings (jq or python3 required). Keeping existing settings.\n"
    return 0
  fi

  # Validate existing JSON
  local is_valid=0
  if [ "$tool" = "jq" ]; then
    jq empty "$settings_file" > /dev/null 2>&1 || is_valid=1
  else
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$settings_file" > /dev/null 2>&1 || is_valid=1
  fi

  if [ $is_valid -ne 0 ]; then
    rm -f "$tmpfile"
    printf "❌ Error: Existing settings file %s contains invalid JSON.\n" "$settings_file"
    return 1
  fi

  # Merge to temp settings.json
  local merge_success=0
  if [ "$tool" = "jq" ]; then
    jq -s '.[0] * .[1]' "$settings_file" <(printf '%s\n' "$new_settings") > "$tmpfile" 2> /dev/null || merge_success=1
  else
    python3 -c "import json,sys;m=lambda a,b:{**a,**{k:m(a[k],v)if k in a and type(a[k])==type(v)==dict else v for k,v in b.items()}};print(json.dumps(m(json.load(open(sys.argv[1])),json.loads(sys.argv[2])),indent=2))" "$settings_file" "$new_settings" > "$tmpfile" 2> /dev/null || merge_success=1
  fi

  # Update settings.json with the newly merged configuration
  if [ $merge_success -eq 0 ]; then
    mv "$tmpfile" "$settings_file"
    printf "⚙️ Merging settings...\n"
    return 0
  else
    rm -f "$tmpfile"
    printf "❌ Error: %s failed to write the new settings file %s.\n" "$tool" "$settings_file"
    return 1
  fi
}

# Apply user settings (merge or overwrite based on flag)
SETTINGS_B64='${SETTINGS_B64}'
if [ -n "$SETTINGS_B64" ]; then
  if SETTINGS_JSON="$(echo -n "$SETTINGS_B64" | base64 -d 2> /dev/null)" && [ -n "$SETTINGS_JSON" ]; then
    # Return 1 triggers exit 1 to halt execution if validation fails
    save_settings "$SETTINGS_JSON" ~/.local/share/code-server/User/settings.json "${OVERWRITE_SETTINGS}" || exit 1
  else
    printf "Warning: Failed to decode settings. Skipping settings configuration.\n"
  fi
fi

# Apply machine settings (merge or overwrite based on flag)
MACHINE_SETTINGS_B64='${MACHINE_SETTINGS_B64}'
if [ -n "$MACHINE_SETTINGS_B64" ]; then
  if MACHINE_SETTINGS_JSON="$(echo -n "$MACHINE_SETTINGS_B64" | base64 -d 2> /dev/null)" && [ -n "$MACHINE_SETTINGS_JSON" ]; then
    # Return 1 triggers exit 1 to halt execution if validation fails
    save_settings "$MACHINE_SETTINGS_JSON" ~/.local/share/code-server/Machine/settings.json "${OVERWRITE_MACHINE_SETTINGS}" || exit 1
  else
    printf "Warning: Failed to decode machine settings. Skipping machine settings configuration.\n"
  fi
fi

# Check if code-server is already installed for offline
if [ "${OFFLINE}" = true ]; then
  if [ -f "$CODE_SERVER" ]; then
    echo "🥳 Found a copy of code-server"
    run_code_server
    exit 0
  fi
  # Offline mode always expects a copy of code-server to be present
  echo "Failed to find a copy of code-server"
  exit 1
fi

# If there is no cached install OR we don't want to use a cached install
if [ ! -f "$CODE_SERVER" ] || [ "${USE_CACHED}" != true ]; then
  printf "$${BOLD}Installing code-server!\n"

  # Clean up from other install (in case install prefix changed).
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ -e "$CODER_SCRIPT_BIN_DIR/code-server" ]; then
    rm "$CODER_SCRIPT_BIN_DIR/code-server"
  fi

  ARGS=(
    "--method=standalone"
    "--prefix=${INSTALL_PREFIX}"
  )
  if [ -n "${VERSION}" ]; then
    ARGS+=("--version=${VERSION}")
  fi

  output=$(curl -fsSL https://code-server.dev/install.sh | sh -s -- "$${ARGS[@]}")
  if [ $? -ne 0 ]; then
    echo "Failed to install code-server: $output"
    exit 1
  fi
  printf "🥳 code-server has been installed in ${INSTALL_PREFIX}\n\n"
fi

# Make the code-server available in PATH.
if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/code-server" ]; then
  ln -s "$CODE_SERVER" "$CODER_SCRIPT_BIN_DIR/code-server"
fi

# Get the list of installed extensions...
LIST_EXTENSIONS=$($CODE_SERVER --list-extensions $EXTENSION_ARG)
readarray -t EXTENSIONS_ARRAY <<< "$LIST_EXTENSIONS"
function extension_installed() {
  if [ "${USE_CACHED_EXTENSIONS}" != true ]; then
    return 1
  fi
  # shellcheck disable=SC2066
  for _extension in "$${EXTENSIONS_ARRAY[@]}"; do
    if [ "$_extension" == "$1" ]; then
      echo "Extension $1 was already installed."
      return 0
    fi
  done
  return 1
}

# Install each extension...
IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
# shellcheck disable=SC2066
for extension in "$${EXTENSIONLIST[@]}"; do
  if [ -z "$extension" ]; then
    continue
  fi
  if extension_installed "$extension"; then
    continue
  fi
  printf "🧩 Installing extension $${CODE}$extension$${RESET}...\n"
  output=$($CODE_SERVER "$EXTENSION_ARG" --force --install-extension "$extension")
  if [ $? -ne 0 ]; then
    echo "Failed to install extension: $extension: $output"
    exit 1
  fi
done

if [ "${AUTO_INSTALL_EXTENSIONS}" = true ]; then
  if ! command -v jq > /dev/null; then
    echo "jq is required to install extensions from a workspace file."
    exit 0
  fi

  RECOMMENDATIONS_FILE=""
  RECOMMENDATIONS_QUERY=".recommendations[]"
  if [ -n "${WORKSPACE}" ]; then
    if [ -f "${WORKSPACE}" ]; then
      RECOMMENDATIONS_FILE="${WORKSPACE}"
      RECOMMENDATIONS_QUERY=".extensions.recommendations[]?"
    else
      echo "⚠️ Workspace file ${WORKSPACE} not found, skipping extension recommendations."
    fi
  else
    WORKSPACE_DIR="$HOME"
    if [ -n "${FOLDER}" ]; then
      WORKSPACE_DIR="${FOLDER}"
    fi
    if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
      RECOMMENDATIONS_FILE="$WORKSPACE_DIR/.vscode/extensions.json"
    fi
  fi

  if [ -n "$RECOMMENDATIONS_FILE" ]; then
    printf "🧩 Installing extensions from %s...\n" "$RECOMMENDATIONS_FILE"
    # Use sed to remove single-line comments before parsing with jq
    extensions=$(sed 's|//.*||g' "$RECOMMENDATIONS_FILE" | jq -r "$RECOMMENDATIONS_QUERY")
    for extension in $extensions; do
      if extension_installed "$extension"; then
        continue
      fi
      $CODE_SERVER "$EXTENSION_ARG" --force --install-extension "$extension"
    done
  fi
fi

run_code_server
