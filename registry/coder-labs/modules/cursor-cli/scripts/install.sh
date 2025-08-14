#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Inputs
ARG_INSTALL=${ARG_INSTALL:-true}
ARG_MODULE_DIR_NAME=${ARG_MODULE_DIR_NAME:-.cursor-cli-module}
ARG_FOLDER=${ARG_FOLDER:-$HOME}
ARG_CODER_MCP_APP_STATUS_SLUG=${ARG_CODER_MCP_APP_STATUS_SLUG:-}

mkdir -p "$HOME/$ARG_MODULE_DIR_NAME"

ARG_WORKSPACE_MCP_JSON=$(echo -n "$ARG_WORKSPACE_MCP_JSON" | base64 -d)
ARG_WORKSPACE_RULES_JSON=$(echo -n "$ARG_WORKSPACE_RULES_JSON" | base64 -d)

echo "--------------------------------"
echo "install: $ARG_INSTALL"
echo "folder: $ARG_FOLDER"
echo "coder_mcp_app_status_slug: $ARG_CODER_MCP_APP_STATUS_SLUG"
echo "module_dir_name: $ARG_MODULE_DIR_NAME"
echo "--------------------------------"

# Install Cursor via official installer if requested
function install_cursor_cli() {
  if [ "$ARG_INSTALL" = "true" ]; then
    echo "Installing Cursor via official installer..."
    set +e
    curl https://cursor.com/install -fsS | bash 2>&1
    CURL_EXIT=${PIPESTATUS[0]}
    set -e
    if [ $CURL_EXIT -ne 0 ]; then
      echo "Cursor installer failed with exit code $CURL_EXIT"
    fi

    # Ensure binaries are discoverable; create stable symlink to cursor-agent
    CANDIDATES=(
      "$(command -v cursor-agent || true)"
      "$HOME/.cursor/bin/cursor-agent"
    )
    FOUND_BIN=""
    for c in "${CANDIDATES[@]}"; do
      if [ -n "$c" ] && [ -x "$c" ]; then
        FOUND_BIN="$c"
        break
      fi
    done
    mkdir -p "$HOME/.local/bin"
    if [ -n "$FOUND_BIN" ]; then
      ln -sf "$FOUND_BIN" "$HOME/.local/bin/cursor-agent"
    fi
    echo "Installed cursor-agent at: $(command -v cursor-agent || true) (resolved: $FOUND_BIN)"
  fi
}

# Write MCP config to user's home if provided (ARG_FOLDER/.cursor/mcp.json)
function write_mcp_config() {
  TARGET_DIR="$ARG_FOLDER/.cursor"
  TARGET_FILE="$TARGET_DIR/mcp.json"
  mkdir -p "$TARGET_DIR"

  CURSOR_MCP_HACK_SCRIPT=$(
    cat << EOF
#!/usr/bin/env bash
set -e

# --- Set environment variables ---
export CODER_MCP_APP_STATUS_SLUG="${ARG_CODER_MCP_APP_STATUS_SLUG}"
export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
export CODER_AGENT_URL="${CODER_AGENT_URL}"
export CODER_AGENT_TOKEN="${CODER_AGENT_TOKEN}"

# --- Launch the MCP server ---
exec coder exp mcp server
EOF
  )
  echo "$CURSOR_MCP_HACK_SCRIPT" > "/tmp/mcp-hack.sh"
  chmod +x /tmp/mcp-hack.sh

  CODER_MCP=$(
    cat << EOF
{
 "coder": {
   "args": [],
   "command": "/tmp/mcp-hack.sh",
   "description": "Report ALL tasks and statuses (in progress, done, failed) you are working on.",
   "name": "Coder",
   "timeout": 3000,
   "type": "stdio",
   "trust": true
 }
}
EOF
  )

  echo "${ARG_WORKSPACE_MCP_JSON:-{}}" | jq --argjson base "$CODER_MCP" \
    '.mcpServers = ((.mcpServers // {}) + $base)' > "$TARGET_FILE"
  echo "Wrote workspace MCP to $TARGET_FILE"
}

# Write rules files to user's home (FOLDER/.cursor/rules)
function write_rules_file() {
  if [ -n "$ARG_WORKSPACE_RULES_JSON" ]; then
    RULES_DIR="$ARG_FOLDER/.cursor/rules"
    mkdir -p "$RULES_DIR"
    echo "$ARG_WORKSPACE_RULES_JSON" | jq -r 'to_entries[] | @base64' | while read -r entry; do
      _jq() { echo "${entry}" | base64 -d | jq -r ${1}; }
      NAME=$(_jq '.key')
      CONTENT=$(_jq '.value')
      echo "$CONTENT" > "$RULES_DIR/$NAME"
      echo "Wrote rule: $RULES_DIR/$NAME"
    done
  fi
}

install_cursor_cli
write_mcp_config
write_rules_file
