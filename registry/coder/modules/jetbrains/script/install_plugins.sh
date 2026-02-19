#!/bin/bash
set -euo pipefail

LOGFILE="$HOME/.config/jetbrains/install_plugins.log"
CONFIG_DIR="$HOME/.config/jetbrains"
PLUGIN_MAP="$CONFIG_DIR/plugins.json"
IDE_BASE="$HOME/.local/share/JetBrains"

mkdir -p "$CONFIG_DIR"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

# ---------- Read config ----------
get_enabled_codes() {
  jq -r 'keys[]' "$PLUGIN_MAP"
}

get_plugins_for_code() {
  jq -r --arg CODE "$1" '.[$CODE][]?' "$PLUGIN_MAP"
}

get_build_for_code() {
  case "$1" in
    CL) echo "253.29346.141" ;;
    GO) echo "253.28294.337" ;;
    IU) echo "253.29346.138" ;;
    PS) echo "253.29346.151" ;;
    PY) echo "253.29346.142" ;;
    RD) echo "253.29346.144" ;;
    RM) echo "253.29346.140" ;;
    RR) echo "253.29346.139" ;;
    WS) echo "253.29346.143" ;;
    *) return 1 ;;
  esac
}

get_name_for_code() {
  case "$1" in
    CL) echo "CLion" ;;
    GO) echo "GoLand" ;;
    IU) echo "IntelliJIdea" ;;
    PS) echo "PhpStorm" ;;
    PY) echo "PyCharm" ;;
    RD) echo "Rider" ;;
    RM) echo "RubyMine" ;;
    RR) echo "ReSharper" ;;
    WS) echo "WebStorm" ;;
    *) return 1 ;;
  esac
}

get_data_dir_for_code() {
  local code="$1"
  local build="$2"

  local name
  local build_prefix
  local year
  local minor

  name="$(get_name_for_code "$code")"

  # build = 253.29346.142 → prefix = 253
  build_prefix="${build%%.*}"

  # 253 → 2025.3
  year="20${build_prefix:0:2}"
  minor="${build_prefix:2:1}"

  printf '%s%s.%s\n' "$name" "$year" "$minor"
}

# ---------- Plugin installer ----------
install_plugin() {
  local code="$1"
  local build="$2"
  local dataDir="$3"
  local pluginId="$4"

  local name
  name="$(get_name_for_code "$code")"

  local plugins_dir="$IDE_BASE/$dataDir"
  mkdir -p "$plugins_dir"

  local url="https://plugins.jetbrains.com/pluginManager?action=download&id=$pluginId&build=$code-$build"

  local workdir
  workdir="$(mktemp -d)"
  cd "$workdir"

  log "[$name]" "Downloading $pluginId ($code-$build)"

  if ! curl -fsSL -OJ "$url"; then
    log "Download failed: $pluginId"
    rm -rf "$workdir"
    return 1
  fi

  # We expect exactly one file after download
  file="$(ls)"

  # ---------- ZIP plugin ----------
  if unzip -t "$file" > /dev/null 2>&1; then
    unzip -qq "$file"

    entries=(*)
    log "[$name]" "Extracted $file, found entries: ${entries[*]}"

    if [ -d "${entries[0]}" ] && [ -d "${entries[0]}/lib" ]; then
      cp -r "${entries[0]}" "$plugins_dir/"
      log "[$name]" "Installed ZIP plugin $pluginId"
    elif [[ "$file" == *.jar ]]; then
      cp "$file" "$plugins_dir/"
      log "[$name]" "Installed JAR plugin $pluginId"
    fi
  fi

  cd /
  rm -rf "$workdir"
}

# ---------- Main ----------
log "Plugin installer started (build-based mode)"

[ ! -f "$PLUGIN_MAP" ] && log "No plugins.json found" && exit 0

get_enabled_codes | while read -r code; do
  build="$(get_build_for_code "$code")"
  dataDir="$(get_data_dir_for_code "$code" "$build")"

  if [ -z "$build" ] || [ -z "$dataDir" ]; then
    log "Missing config for $code, skipping"
    continue
  fi

  get_plugins_for_code "$code" | while read -r plugin; do
    [ -n "$plugin" ] && install_plugin "$code" "$build" "$dataDir" "$plugin" || continue
  done
done

log "All plugins processed"
