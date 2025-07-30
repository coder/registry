#!/bin/bash

BOLD='\033[0;1m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set -o nounset

ARG_GEMINI_CONFIG=$(echo -n "$ARG_GEMINI_CONFIG" | base64 -d)
BASE_EXTENSIONS=$(echo -n "$BASE_EXTENSIONS" | base64 -d)
ADDITIONAL_EXTENSIONS=$(echo -n "$ADDITIONAL_EXTENSIONS" | base64 -d)
GEMINI_INSTRUCTION_PROMPT=$(echo -n "$GEMINI_INSTRUCTION_PROMPT" | base64 -d)

echo "--------------------------------"
printf "gemini_config: %s\n" "$ARG_GEMINI_CONFIG"
printf "install: %s\n" "$ARG_INSTALL"
printf "gemini_version: %s\n" "$ARG_GEMINI_VERSION"
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

        printf "Node.js installed: %s\n" "$(node --version)"
        printf "npm installed: %s\n" "$(npm --version)"
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

  # If nvm does not exist, we will create a global npm directory (this os to prevent the possibility of EACCESS issues on npm -g)
  if ! command_exists nvm; then
      printf "which node: %s\n" "$(which node)"
      printf "which npm: %s\n" "$(which npm)"

      # Create a directory for global packages
      mkdir -p "$HOME"/.npm-global

      # Configure npm to use it
      npm config set prefix "$HOME/.npm-global"

      # Add to PATH for current session
      export PATH="$HOME/.npm-global/bin:$PATH"

      # Add to shell profile for future sessions
      if ! grep -q "export PATH=$HOME/.npm-global/bin:\$PATH" ~/.bashrc; then
          echo "export PATH=$HOME/.npm-global/bin:\$PATH" >> ~/.bashrc
      fi
    fi

    printf "%s Installing Gemini CLI\n" "${BOLD}"

    if [ -n "$ARG_GEMINI_VERSION" ]; then
      npm install -g "@google/gemini-cli@$ARG_GEMINI_VERSION"
    else
      npm install -g "@google/gemini-cli"
    fi
    printf "%s Successfully installed Gemini CLI. Version: %s\n" "${BOLD}" "$(gemini --version)"
  fi
}

function populate_settings_json() {
    if [ "${ARG_GEMINI_CONFIG}" != "" ]; then
      SETTINGS_PATH="$HOME/.gemini/settings.json"
      mkdir -p "$(dirname "$SETTINGS_PATH")"
      printf "Custom gemini_config is provided !\n"
      echo "${ARG_GEMINI_CONFIG}" > "$HOME/.gemini/settings.json"
    else
      printf "No custom gemini_config provided, using default settings.json.\n"
      append_extensions_to_settings_json
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
      printf "%s does not exist. Creating with merged mcpServers structure.\n" "$SETTINGS_PATH"
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
gemini --version
populate_settings_json
add_instruction_prompt_if_exists

