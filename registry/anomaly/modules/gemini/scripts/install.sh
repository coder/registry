#!/bin/bash

BOLD='\033[0;1m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
printf "gemini_config: %s\n" "$ARG_GEMINI_CONFIG\n"
printf "install: %s\n" "$ARG_INSTALL\n"
printf "gemini_version: %s\n" "$ARG_GEMINI_VERSION\n"
echo "--------------------------------"

set +o nounset

function install_node() {
  # borrowed from claude-code module
    if ! command_exists npm; then
      printf "npm not found, checking for Node.js installation...\n"
      if ! command_exists node; then
        printf "Node.js not found, installing Node.js via NVM...\n"
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
          mkdir -p "$NVM_DIR"
          curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        else
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        fi

        nvm install --lts
        nvm use --lts
        nvm alias default node

        printf "Node.js installed: %s\n" "$(node --version)\n"
        printf "npm installed: %s\n" "$(npm --version)\n"
      else
        printf "Node.js is installed but npm is not available. Please install npm manually.\n"
        exit 1
      fi
    fi
}

function install_gemini() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    # we need node to install and run gemini-cli
    install_node

    printf "%s Installing Gemini CLI\n" "$${BOLD}"
    if [ -n "$ARG_GEMINI_VERSION" ]; then
      npm install -g "@google/gemini-cli@$ARG_GEMINI_VERSION"
    else
      npm install -g "@google/gemini-cli"
    fi
    printf "%s Successfully installed Gemini CLI. Version: %s" "$${BOLD}" "$(gemini --version)\n"
  fi
}

function populate_settings_json() {
    if [ "${ARG_GEMINI_CONFIG}" != "" ]; then
      echo "${ARG_GEMINI_CONFIG}" > "$HOME/.gemini/settings.json"
    fi
}

function append_extensions_to_settings_json() {
    SETTINGS_PATH="$HOME/.gemini/settings.json"
    mkdir -p "$(dirname "$SETTINGS_PATH")"
    printf "[append_extensions_to_settings_json] Starting extension merge process...\n"
    if [ -z "${BASE_EXTENSIONS:-}" ]; then
      printf "[append_extensions_to_settings_json] BASE_EXTENSIONS is empty, skipping merge.\n"
      return
    fi
    if [ ! -f "$SETTINGS_PATH" ]; then
      printf "[append_extensions_to_settings_json] $SETTINGS_PATH does not exist. Creating with merged mcpServers structure.\n"
      # If ADDITIONAL_EXTENSIONS is not set or empty, use '{}'
      ADD_EXT_JSON='{}'
      if [ -n "${ADDITIONAL_EXTENSIONS:-}" ]; then
        ADD_EXT_JSON="$ADDITIONAL_EXTENSIONS"
      fi
      printf '{"mcpServers":%s}\n' "$(jq -s 'add' <(echo "$BASE_EXTENSIONS") <(echo "$ADD_EXT_JSON"))" > "$SETTINGS_PATH"
    fi

    # Prepare temp files
    TMP_SETTINGS=$(mktemp)

    # If ADDITIONAL_EXTENSIONS is not set or empty, use '{}'
    ADD_EXT_JSON='{}'
    if [ -n "${ADDITIONAL_EXTENSIONS:-}" ]; then
      printf "[append_extensions_to_settings_json] ADDITIONAL_EXTENSIONS is set.\n"
      ADD_EXT_JSON="$ADDITIONAL_EXTENSIONS"
    else
      printf "[append_extensions_to_settings_json] ADDITIONAL_EXTENSIONS is empty or not set.\n"
    fi

    printf "[append_extensions_to_settings_json] Merging BASE_EXTENSIONS and ADDITIONAL_EXTENSIONS into mcpServers...\n"
    jq --argjson base "$BASE_EXTENSIONS" --argjson add "$ADD_EXT_JSON" \
      '.mcpServers = (.mcpServers // {} + $base + $add)' \
      "$SETTINGS_PATH" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_PATH"

    # Add theme and selectedAuthType fields
    jq '.theme = "Default" | .selectedAuthType = "gemini-api-key"' "$SETTINGS_PATH" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_PATH"

    printf "[append_extensions_to_settings_json] Merge complete.\n"
}

function add_instruction_prompt_if_exists() {
    if [ -n "${GEMINI_INSTRUCTION_PROMPT:-}" ]; then
        if [ -d "${GEMINI_START_DIRECTORY}" ]; then
            printf "Directory '%s' exists. Changing to it.\\n" "${GEMINI_START_DIRECTORY}"
            cd "${GEMINI_START_DIRECTORY}" || {
                printf "Error: Could not change to directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
                exit 1
            }
        else
            printf "Directory '%s' does not exist. Creating and changing to it.\\n" "${GEMINI_START_DIRECTORY}"
            mkdir -p "${GEMINI_START_DIRECTORY}" || {
                printf "Error: Could not create directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
                exit 1
            }
            cd "${GEMINI_START_DIRECTORY}" || {
                printf "Error: Could not change to directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
                exit 1
            }
        fi
        touch GEMINI.md
        printf "Setting GEMINI.md\n"
        echo "${GEMINI_INSTRUCTION_PROMPT}" > GEMINI.md
    else
        printf "GEMINI.md is not set.\n"
    fi
}


# Install Gemini
install_gemini
populate_settings_json
gemini --version
append_extensions_to_settings_json
add_instruction_prompt_if_exists

