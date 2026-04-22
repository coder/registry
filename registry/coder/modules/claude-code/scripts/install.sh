#!/bin/bash

set -euo pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_CLAUDE_CODE_VERSION=${ARG_CLAUDE_CODE_VERSION:-}
ARG_INSTALL_CLAUDE_CODE=${ARG_INSTALL_CLAUDE_CODE:-true}
ARG_CLAUDE_BINARY_PATH=${ARG_CLAUDE_BINARY_PATH:-"$HOME/.local/bin"}
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH/#\~/$HOME}"
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH//\$HOME/$HOME}"
ARG_MCP=$(echo -n "${ARG_MCP:-}" | base64 -d)
ARG_MCP_CONFIG_REMOTE_PATH=$(echo -n "${ARG_MCP_CONFIG_REMOTE_PATH:-}" | base64 -d)

export PATH="$ARG_CLAUDE_BINARY_PATH:$PATH"

echo "--------------------------------"
printf "ARG_CLAUDE_CODE_VERSION: %s\n" "$ARG_CLAUDE_CODE_VERSION"
printf "ARG_INSTALL_CLAUDE_CODE: %s\n" "$ARG_INSTALL_CLAUDE_CODE"
printf "ARG_CLAUDE_BINARY_PATH: %s\n" "$ARG_CLAUDE_BINARY_PATH"
printf "ARG_MCP: %s\n" "$ARG_MCP"
printf "ARG_MCP_CONFIG_REMOTE_PATH: %s\n" "$ARG_MCP_CONFIG_REMOTE_PATH"
echo "--------------------------------"

# Ensures $ARG_CLAUDE_BINARY_PATH is on PATH across the common shell profiles so
# interactive shells started by the user can find the installed claude binary.
add_path_to_shell_profiles() {
  local path_dir="$1"

  for profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do
    if [ -f "$profile" ]; then
      if ! grep -q "$path_dir" "$profile" 2> /dev/null; then
        echo "export PATH=\"\$PATH:$path_dir\"" >> "$profile"
        echo "Added $path_dir to $profile"
      fi
    fi
  done

  local fish_config="$HOME/.config/fish/config.fish"
  if [ -f "$fish_config" ]; then
    if ! grep -q "$path_dir" "$fish_config" 2> /dev/null; then
      echo "fish_add_path $path_dir" >> "$fish_config"
      echo "Added $path_dir to $fish_config"
    fi
  fi
}

# Resolves the claude binary, symlinks it into CODER_SCRIPT_BIN_DIR so the
# agent's coder_script context can call it, and updates shell profiles.
ensure_claude_in_path() {
  local CLAUDE_BIN=""
  if command -v claude > /dev/null 2>&1; then
    CLAUDE_BIN=$(command -v claude)
  elif [ -x "$ARG_CLAUDE_BINARY_PATH/claude" ]; then
    CLAUDE_BIN="$ARG_CLAUDE_BINARY_PATH/claude"
  elif [ -x "$HOME/.local/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
  fi

  if [ -z "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
    echo "Warning: Could not find claude binary"
    return
  fi

  local CLAUDE_DIR
  CLAUDE_DIR=$(dirname "$CLAUDE_BIN")

  if [ -n "${CODER_SCRIPT_BIN_DIR:-}" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/claude" ]; then
    ln -s "$CLAUDE_BIN" "$CODER_SCRIPT_BIN_DIR/claude"
    echo "Created symlink: $CODER_SCRIPT_BIN_DIR/claude -> $CLAUDE_BIN"
  fi

  add_path_to_shell_profiles "$CLAUDE_DIR"
}

# Adds each MCP server from the provided JSON at user scope. The claude CLI
# writes to ~/.claude.json; this module does not touch that file directly.
add_mcp_servers() {
  local mcp_json="$1"
  local source_desc="$2"

  while IFS= read -r server_name && IFS= read -r server_json; do
    echo "------------------------"
    echo "Executing: claude mcp add-json --scope user \"$server_name\" ($source_desc)"
    claude mcp add-json --scope user "$server_name" "$server_json" \
      || echo "Warning: Failed to add MCP server '$server_name', continuing..."
    echo "------------------------"
  done < <(echo "$mcp_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
}

install_claude_code_cli() {
  if [ "$ARG_INSTALL_CLAUDE_CODE" != "true" ]; then
    echo "Skipping Claude Code installation as per configuration."
    ensure_claude_in_path
    return
  fi

  echo "Installing Claude Code via official installer (version: $ARG_CLAUDE_CODE_VERSION)"
  set +e
  curl -fsSL https://claude.ai/install.sh | bash -s -- "$ARG_CLAUDE_CODE_VERSION" 2>&1
  CURL_EXIT=${PIPESTATUS[0]}
  set -e
  if [ "$CURL_EXIT" -ne 0 ]; then
    echo "Claude Code installer failed with exit code $CURL_EXIT"
    exit "$CURL_EXIT"
  fi
  echo "Installed Claude Code successfully. Version: $(claude --version || echo 'unknown')"

  ensure_claude_in_path
}

apply_mcp() {
  if [ -n "$ARG_MCP" ]; then
    add_mcp_servers "$ARG_MCP" "inline"
  fi

  if [ -n "$ARG_MCP_CONFIG_REMOTE_PATH" ] && [ "$ARG_MCP_CONFIG_REMOTE_PATH" != "[]" ]; then
    for url in $(echo "$ARG_MCP_CONFIG_REMOTE_PATH" | jq -r '.[]'); do
      echo "Fetching MCP configuration from: $url"
      mcp_json=$(curl -fsSL "$url") || {
        echo "Warning: Failed to fetch MCP configuration from '$url', continuing..."
        continue
      }
      if ! echo "$mcp_json" | jq -e '.mcpServers' > /dev/null 2>&1; then
        echo "Warning: Invalid MCP configuration from '$url' (missing mcpServers), continuing..."
        continue
      fi
      add_mcp_servers "$mcp_json" "from $url"
    done
  fi
}

install_claude_code_cli
apply_mcp
