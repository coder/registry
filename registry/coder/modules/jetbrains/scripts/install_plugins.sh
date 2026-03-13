#!/bin/bash
# set -euo pipefail

LOGFILE="$HOME/.config/jetbrains/install_plugins.log"
TOOLBOX_BASE="$HOME/.local/share/JetBrains/Toolbox/apps"
PLUGIN_MAP_FILE="$HOME/.config/jetbrains/plugins.json"
PLUGIN_ALREADY_INSTALLED_MAP="$HOME/.config/jetbrains"

# -------- Install dependencies --------
install_dependencies() {
  if command -v apt-get > /dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y libfreetype6 jq
  elif command -v dnf > /dev/null 2>&1; then
    sudo dnf install -y freetype-devel jq
  elif command -v yum > /dev/null 2>&1; then
    sudo yum install -y freetype-devel jq
  elif command -v pacman > /dev/null 2>&1; then
    sudo pacman -Sy --noconfirm freetype2 jq
  elif command -v apk > /dev/null 2>&1; then
    sudo apk add --no-cache freetype-dev jq
  else
    echo "Warning: Package manager not found. Please ensure 'libfreetype6' and 'jq' are installed manually for your distribution." >&2
    return 1
  fi
}

install_dependencies || true

# Verify jq is available
if ! command -v jq > /dev/null 2>&1; then
  echo "Error: 'jq' is required but not installed. Please install it manually." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOGFILE")"

exec > >(tee -a "$LOGFILE") 2>&1

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

# -------- Read plugin JSON --------
get_enabled_codes() {
  jq -r 'keys[]' "$PLUGIN_MAP_FILE"
}

get_plugins_for_code() {
  jq -r --arg CODE "$1" '.[$CODE][]?' "$PLUGIN_MAP_FILE" 2> /dev/null || true
}

# Returns only plugins that are NOT already installed
check_plugins_installed() {
  local code="$1"
  shift
  local plugins=("$@")

  local installed_file="$PLUGIN_ALREADY_INSTALLED_MAP/${code}_installed.json"

  # If no installed file exists, all plugins need to be installed
  if [ ! -f "$installed_file" ]; then
    printf '%s\n' "${plugins[@]}"
    return 0
  fi

  installed_plugins=$(jq -r '.[]?' "$installed_file" 2> /dev/null)

  for plugin in "${plugins[@]}"; do
    if ! echo "$installed_plugins" | grep -Fxq "$plugin"; then
      echo "$plugin"
    fi
  done
  return 0
}

# -------- Product code mapping --------
map_folder_to_code() {
  case "$1" in
    *pycharm*) echo "PY" ;;
    *idea*) echo "IU" ;;
    *webstorm*) echo "WS" ;;
    *goland*) echo "GO" ;;
    *clion*) echo "CL" ;;
    *phpstorm*) echo "PS" ;;
    *rider*) echo "RD" ;;
    *rubymine*) echo "RM" ;;
    *rustrover*) echo "RR" ;;
    *) echo "" ;;
  esac
}

# -------- CLI launcher names --------
launcher_for_code() {
  case "$1" in
    PY) echo "pycharm" ;;
    IU) echo "idea" ;;
    WS) echo "webstorm" ;;
    GO) echo "goland" ;;
    CL) echo "clion" ;;
    PS) echo "phpstorm" ;;
    RD) echo "rider" ;;
    RM) echo "rubymine" ;;
    RR) echo "rustrover" ;;
    *) return 1 ;;
  esac
}

find_cli_launcher() {
  local exe
  exe="$(launcher_for_code "$1")" || return 1

  # Look for the newest version directory
  local latest_version
  latest_version=$(find "$2" -maxdepth 2 -type d -name "ch-*" 2> /dev/null | sort -V | tail -1)

  if [ -n "$latest_version" ] && [ -f "$latest_version/bin/$exe" ]; then
    echo "$latest_version/bin/$exe"
  elif [ -f "$2/bin/$exe" ]; then
    echo "$2/bin/$exe"
  else
    return 1
  fi
}

# Marks a plugin as installed by adding it to the installed plugins JSON file
mark_plugins_installed() {
  local code="$1"
  local plugin="$2"

  local installed_file="$PLUGIN_ALREADY_INSTALLED_MAP/${code}_installed.json"

  mkdir -p "$PLUGIN_ALREADY_INSTALLED_MAP"

  # Create file with empty array if it doesn't exist
  if [ ! -f "$installed_file" ]; then
    echo '[]' > "$installed_file" || {
      log "Error: Failed to create $installed_file"
      return 1
    }
  fi

  jq --arg PLUGIN "$plugin" '. += [$PLUGIN]' "$installed_file" > "${installed_file}.tmp" 2> /dev/null \
    && mv "${installed_file}.tmp" "$installed_file" || {
    log "Error: Failed to update $installed_file with plugin $plugin"
    rm -f "${installed_file}.tmp"
    return 1
  }
  log "Marked plugin as installed: $plugin"
  return 0
}

install_plugin() {
  log "Installing plugin: $2"
  if "$1" installPlugins "$2"; then
    log "Successfully installed plugin: $2"
    return 0
  else
    log "Failed to install plugin: $2"
    return 1
  fi
}

# -------- Main --------
log "Plugin installer started"

if [ ! -f "$PLUGIN_MAP_FILE" ]; then
  log "No plugins.json found. Exiting."
  exit 0
fi

if [ ! -d "$TOOLBOX_BASE" ]; then
  log "Toolbox directory not found. Exiting."
  exit 0
fi

# Load list of IDE codes user actually needs
mapfile -t pending_codes < <(get_enabled_codes)

if [ ${#pending_codes[@]} -eq 0 ]; then
  log "No plugin entries found. Exiting."
  exit 0
fi

log "Waiting for IDE installation. Pending codes: ${pending_codes[*]}"

# Loop until all plugins installed
for product_dir in "$TOOLBOX_BASE"/*; do
  [ -d "$product_dir" ] || continue

  product_name="$(basename "$product_dir")"
  code="$(map_folder_to_code "$product_name")"

  # Only process codes user requested
  if [[ ! " ${pending_codes[*]} " =~ " $code " ]]; then
    continue
  fi

  # Store plugins as array for consistency
  mapfile -t plugins_list < <(get_plugins_for_code "$code")
  if [ ${#plugins_list[@]} -eq 0 ]; then
    log "No plugins for $code"
    continue
  fi

  # Get only plugins that are not already installed
  mapfile -t new_plugins < <(check_plugins_installed "$code" "${plugins_list[@]}")
  if [ ${#new_plugins[@]} -eq 0 ]; then
    log "All plugins for $code are already installed"
    # Remove code from pending list since all plugins are installed
    tmp=()
    for c in "${pending_codes[@]}"; do
      [ "$c" != "$code" ] && tmp+=("$c")
    done
    pending_codes=("${tmp[@]}")
    continue
  fi

  cli_launcher_path="$(find_cli_launcher "$code" "$product_dir")" || continue
  log "Detected IDE $code at $product_dir"
  log "Plugins to install for $code: ${#new_plugins[@]} plugin(s)"

  # Install only the plugins that are not yet installed
  for plugin in "${new_plugins[@]}"; do
    if install_plugin "$cli_launcher_path" "$plugin"; then
      # Mark plugin as installed after successful installation
      mark_plugins_installed "$code" "$plugin"
    fi
  done

  # remove code from pending list after success
  tmp=()
  for c in "${pending_codes[@]}"; do
    [ "$c" != "$code" ] && tmp+=("$c")
  done
  pending_codes=("${tmp[@]}")
  log "Finished $code. Remaining: ${pending_codes[*]:-none}"
done

if [ ${#pending_codes[@]} -gt 0 ]; then
  log "These IDEs not found: ${pending_codes[*]}"
fi

log "Exiting."
