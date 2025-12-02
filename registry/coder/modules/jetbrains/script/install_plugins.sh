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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}


# -------- Read plugin JSON --------
get_plugins_for_code() {
  local code="$1"
  jq -r --arg CODE "$code" '.[$CODE][]?' "$PLUGIN_MAP_FILE" 2>/dev/null || true
}

# -------- Product code matching from folder name --------
map_folder_to_code() {
  local folder="$1"
  case "$folder" in
    *pycharm*)    echo "PY" ;;
    *idea*)       echo "IU" ;;
    *webstorm*)   echo "WS" ;;
    *goland*)     echo "GO" ;;
    *clion*)      echo "CL" ;;
    *phpstorm*)   echo "PS" ;;
    *rider*)      echo "RD" ;;
    *rubymine*)   echo "RM" ;;
    *rustrover*)  echo "RR" ;;
    *)            echo "" ;;
  esac
}

# -------- Correct launcher per product --------
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
    *)  return 1 ;;
  esac
}

find_cli_launcher() {
  local code="$1"
  local product_root="$2"

  local exe
  exe="$(launcher_for_code "$code")" || return 1

  if [ -f "$product_root/bin/$exe" ]; then
    echo "$product_root/bin/$exe"
  else
    return 1
  fi
}

install_plugin() {
  local launcher="$1"
  local plugin="$2"
  log "Installing plugin $plugin"
  "$launcher" installPlugins "$plugin"
}

# -------- Main logic --------
log "Plugin installer started"

if [ ! -f "$PLUGIN_MAP_FILE" ]; then
  log "No plugin map file found. Exiting."
  exit 0
fi

for product_dir in "$TOOLBOX_BASE"/*; do
  [ -d "$product_dir" ] || continue

  product_name="$(basename "$product_dir")"
  code="$(map_folder_to_code "$product_name")"
  [ -n "$code" ] || continue

  cli_launcher="$(find_cli_launcher "$code" "$product_dir")"
  if [ -z "$cli_launcher" ]; then
    log "No CLI launcher found for code $code"
    continue
  fi

  plugins="$(get_plugins_for_code "$code")"
  if [ -z "$plugins" ]; then
    log "No plugins for $code"
    continue
  fi

  while read -r plugin; do
    echo "$cli_launcher and $plugin"
    install_plugin "$cli_launcher" "$plugin"
  done <<< "$plugins"

done

log "Plugin installer finished"
