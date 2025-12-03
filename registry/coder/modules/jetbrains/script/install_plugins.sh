#!/usr/bin/env bash
set -euo pipefail

LOGFILE="$HOME/.config/jetbrains/install_plugins.log"
TOOLBOX_BASE="$HOME/.local/share/JetBrains/Toolbox/apps"
PLUGIN_MAP_FILE="$HOME/.config/jetbrains/plugins.json"

sudo apt-get update
sudo apt-get install -y libfreetype6

mkdir -p "$(dirname "$LOGFILE")"

exec > >(tee -a "$LOGFILE") 2>&1

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$LOGFILE"
}

# -------- Read plugin JSON --------
get_enabled_codes() {
  jq -r 'keys[]' "$PLUGIN_MAP_FILE"
}

get_plugins_for_code() {
  jq -r --arg CODE "$1" '.[$CODE][]?' "$PLUGIN_MAP_FILE" 2> /dev/null || true
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

  if [ -f "$2/bin/$exe" ]; then
    echo "$2/bin/$exe"
  else
    return 1
  fi
}

install_plugin() {
  log "Installing plugin: $2"
  "$1" installPlugins "$2"
}

# -------- Main --------
log "Plugin installer started"

if [ ! -f "$PLUGIN_MAP_FILE" ]; then
  log "No plugins.json found. Exiting."
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
while [ ${#pending_codes[@]} -gt 0 ]; do

  for product_dir in "$TOOLBOX_BASE"/*; do
    [ -d "$product_dir" ] || continue

    product_name="$(basename "$product_dir")"
    code="$(map_folder_to_code "$product_name")"

    # Only process codes user requested
    if [[ ! " ${pending_codes[*]} " =~ " $code " ]]; then
      continue
    fi

    cli_launcher="$(find_cli_launcher "$code" "$product_dir")" || continue

    log "Detected IDE $code at $product_dir"

    plugins="$(get_plugins_for_code "$code")"
    if [ -z "$plugins" ]; then
      log "No plugins for $code"
      continue
    fi

    while read -r plugin; do
      install_plugin "$cli_launcher" "$plugin"
    done <<< "$plugins"

    # remove code from pending list after success
    tmp=()
    for c in "${pending_codes[@]}"; do
      [ "$c" != "$code" ] && tmp+=("$c")
    done
    pending_codes=("${tmp[@]}")

    log "Finished $code. Remaining: ${pending_codes[*]:-none}"

  done

  # If still pending, wait and retry
  if [ ${#pending_codes[@]} -gt 0 ]; then
    sleep 10
  fi
done

log "All plugins installed. Exiting."
