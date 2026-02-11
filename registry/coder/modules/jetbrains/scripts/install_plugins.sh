#!/bin/bash
set -euo pipefail

PLUGIN_IDS="${PLUGIN_IDS:-}"
IDE_CODES="${IDE_CODES:-}"
MARKETPLACE_BASE="https://plugins.jetbrains.com"
TOOLBOX_APPS="$HOME/.local/share/JetBrains/Toolbox/apps"
MAX_WAIT=600 # 10 minutes max wait for IDE installation
POLL_INTERVAL=10

log() {
  printf '[jetbrains-plugins] %s %s\n' "$(date -Iseconds 2> /dev/null || date)" "$*"
}

# Map product code to Toolbox folder name pattern
toolbox_folder_pattern() {
  case "$1" in
    PY) echo "pycharm-professional" ;;
    IU) echo "intellij-idea-ultimate" ;;
    WS) echo "webstorm" ;;
    GO) echo "goland" ;;
    CL) echo "clion" ;;
    PS) echo "phpstorm" ;;
    RD) echo "rider" ;;
    RM) echo "rubymine" ;;
    RR) echo "rustrover" ;;
    *) echo "" ;;
  esac
}

# Map product code to config directory name pattern
config_dir_pattern() {
  case "$1" in
    PY) echo "PyCharm" ;;
    IU) echo "IntelliJIdea" ;;
    WS) echo "WebStorm" ;;
    GO) echo "GoLand" ;;
    CL) echo "CLion" ;;
    PS) echo "PhpStorm" ;;
    RD) echo "Rider" ;;
    RM) echo "RubyMine" ;;
    RR) echo "RustRover" ;;
    *) echo "" ;;
  esac
}

# Find the plugins directory for a given IDE product code.
# Checks multiple known locations:
# 1. Toolbox-managed IDE plugins dir
# 2. RemoteDev dist plugins dir
# 3. Standard config-based plugins dir (~/.local/share/JetBrains/<Product><version>/plugins)
find_plugins_dir() {
  local code="$1"
  local pattern
  local config_pattern

  # 1. Toolbox apps directory
  pattern=$(toolbox_folder_pattern "$code")
  if [ -n "$pattern" ] && [ -d "$TOOLBOX_APPS" ]; then
    for ide_dir in "$TOOLBOX_APPS"/*"$pattern"*; do
      if [ -d "$ide_dir" ]; then
        # Find the latest channel directory (ch-*)
        local ch_dir
        ch_dir=$(find "$ide_dir" -maxdepth 1 -type d -name "ch-*" 2> /dev/null | sort -V | tail -1)
        if [ -n "$ch_dir" ]; then
          # Toolbox plugins go in the channel's plugins subdir
          echo "$ch_dir/plugins"
          return 0
        fi
      fi
    done
  fi

  # 2. RemoteDev dist directory
  for remote_dir in "$HOME"/.cache/JetBrains/RemoteDev/dist/*; do
    if [ -d "$remote_dir" ]; then
      # Check if this dist matches our product code by looking at product-info.json
      if [ -f "$remote_dir/product-info.json" ]; then
        local found_code
        found_code=$(grep -oE '"productCode"[[:space:]]*:[[:space:]]*"[^"]*"' "$remote_dir/product-info.json" 2> /dev/null | head -1 | cut -d'"' -f4)
        if [ "$found_code" = "$code" ]; then
          echo "$remote_dir/plugins"
          return 0
        fi
      fi
    fi
  done

  # 3. Standard config-based plugins directory
  config_pattern=$(config_dir_pattern "$code")
  if [ -n "$config_pattern" ]; then
    for config_dir in "$HOME"/.local/share/JetBrains/"$config_pattern"*/; do
      if [ -d "$config_dir" ]; then
        echo "${config_dir}plugins"
        return 0
      fi
    done
  fi

  return 1
}

# Download and extract a plugin from the JetBrains Marketplace
download_plugin() {
  local plugin_id="$1"
  local product_code="$2"
  local build_number="$3"
  local plugins_dir="$4"

  local download_url="${MARKETPLACE_BASE}/pluginManager?action=download&id=${plugin_id}&build=${product_code}-${build_number}"
  local tmp_file
  tmp_file=$(mktemp /tmp/jb-plugin-XXXXXX.zip)

  log "Downloading plugin '$plugin_id' for $product_code (build $build_number)..."

  local http_code
  http_code=$(curl -fsSL -w "%{http_code}" -o "$tmp_file" "$download_url" 2> /dev/null) || true

  if [ "$http_code" != "200" ] || [ ! -s "$tmp_file" ]; then
    log "WARNING: Failed to download plugin '$plugin_id' (HTTP $http_code). Skipping."
    rm -f "$tmp_file"
    return 1
  fi

  mkdir -p "$plugins_dir"

  # Check if it's a zip or jar
  local file_type
  file_type=$(file -b "$tmp_file" 2> /dev/null || echo "unknown")

  if echo "$file_type" | grep -qi "zip"; then
    # Extract zip — plugins are typically packaged as a directory inside the zip
    if unzip -o -q "$tmp_file" -d "$plugins_dir" 2> /dev/null; then
      log "Installed plugin '$plugin_id' to $plugins_dir"
    else
      log "WARNING: Failed to extract plugin '$plugin_id'. Skipping."
      rm -f "$tmp_file"
      return 1
    fi
  elif echo "$file_type" | grep -qi "java archive\|jar"; then
    # Single jar plugin — copy directly
    local jar_name
    jar_name=$(basename "$plugin_id").jar
    cp "$tmp_file" "$plugins_dir/$jar_name"
    log "Installed plugin jar '$plugin_id' to $plugins_dir/$jar_name"
  else
    # Try unzip anyway — many plugins are zips without proper magic bytes
    if unzip -o -q "$tmp_file" -d "$plugins_dir" 2> /dev/null; then
      log "Installed plugin '$plugin_id' to $plugins_dir"
    else
      log "WARNING: Unknown file type for plugin '$plugin_id'. Skipping."
      rm -f "$tmp_file"
      return 1
    fi
  fi

  rm -f "$tmp_file"
  return 0
}

# -------- Main --------

if [ -z "$PLUGIN_IDS" ]; then
  log "No plugins specified. Exiting."
  exit 0
fi

if [ -z "$IDE_CODES" ]; then
  log "No IDE codes specified. Exiting."
  exit 0
fi

# Parse the JSON plugin config: { "PY": ["plugin1", "plugin2"], "IU": ["plugin3"] }
# IDE_CODES is a comma-separated list of product codes
# PLUGIN_IDS is a base64-encoded JSON map

PLUGIN_MAP=$(echo "$PLUGIN_IDS" | base64 -d 2> /dev/null) || {
  log "ERROR: Failed to decode plugin map. Exiting."
  exit 1
}

log "Plugin pre-installation starting..."
log "IDE codes: $IDE_CODES"

# Build number map is base64-encoded JSON: { "PY": "253.29346.142", "IU": "253.29346.138" }
BUILD_MAP=$(echo "${BUILD_NUMBERS:-}" | base64 -d 2> /dev/null) || BUILD_MAP="{}"

IFS=',' read -ra CODES <<< "$IDE_CODES"

for code in "${CODES[@]}"; do
  code=$(echo "$code" | tr -d ' ')

  # Get plugins for this IDE
  plugins=$(echo "$PLUGIN_MAP" | jq -r --arg c "$code" '.[$c] // [] | .[]' 2> /dev/null) || continue

  if [ -z "$plugins" ]; then
    log "No plugins configured for $code. Skipping."
    continue
  fi

  # Get build number for this IDE
  build=$(echo "$BUILD_MAP" | jq -r --arg c "$code" '.[$c] // ""' 2> /dev/null) || build=""

  if [ -z "$build" ]; then
    log "WARNING: No build number for $code. Will download latest compatible version."
    build=""
  fi

  log "Processing IDE $code (build: ${build:-latest})..."

  # Wait for IDE installation directory to appear
  elapsed=0
  plugins_dir=""
  while [ $elapsed -lt $MAX_WAIT ]; do
    plugins_dir=$(find_plugins_dir "$code" 2> /dev/null) && break
    log "Waiting for $code IDE installation... (${elapsed}s/${MAX_WAIT}s)"
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  if [ -z "$plugins_dir" ]; then
    # IDE not installed yet — pre-create the config-based plugins directory
    # so plugins are ready when the IDE first starts
    config_pattern=$(config_dir_pattern "$code")
    if [ -n "$config_pattern" ] && [ -n "$build" ]; then
      # Derive IDE version from build number (e.g., 253.x -> 2025.3, 242.x -> 2024.2)
      # First 2 digits = year (20XX), 3rd digit = minor version
      build_major=$(echo "$build" | cut -d'.' -f1)
      year_suffix="${build_major:0:2}"
      minor_ver="${build_major:2:1}"
      ide_version="20${year_suffix}.${minor_ver}"
      plugins_dir="$HOME/.local/share/JetBrains/${config_pattern}${ide_version}/plugins"
      log "IDE $code not found. Pre-creating plugins directory: $plugins_dir"
      mkdir -p "$plugins_dir"
    else
      log "WARNING: Could not find or create plugins directory for $code after ${MAX_WAIT}s. Skipping."
      continue
    fi
  fi

  log "Using plugins directory: $plugins_dir"

  # Download and install each plugin
  while IFS= read -r plugin_id; do
    [ -z "$plugin_id" ] && continue
    download_plugin "$plugin_id" "$code" "${build:-}" "$plugins_dir" || true
  done <<< "$plugins"

  log "Finished installing plugins for $code."
done

log "Plugin pre-installation complete."
