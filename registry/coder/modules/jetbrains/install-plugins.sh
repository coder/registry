#!/usr/bin/env bash
# install-plugins.sh - Install JetBrains plugins in workspace IDEs

set -euo pipefail

PLUGINS="${PLUGINS}"
PLUGIN_INSTALL_ARGS="${PLUGIN_INSTALL_ARGS}"
FOLDER="${FOLDER}"
IDE_METADATA='${IDE_METADATA}'

BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "$${BOLD}🔌 JetBrains Plugin Installer$${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Parse plugin list
IFS=',' read -r -a PLUGIN_LIST <<< "$PLUGINS"

if [ $${#PLUGIN_LIST[@]} -eq 0 ] || [ -z "$${PLUGIN_LIST[0]}" ]; then
  echo "No plugins to install."
  exit 0
fi

echo "Plugins to install: $${#PLUGIN_LIST[@]}"
for plugin in "$${PLUGIN_LIST[@]}"; do
  echo "  - $plugin"
done
echo ""

# Parse IDE metadata using jq if available, otherwise use basic parsing
if command -v jq &> /dev/null; then
  IDE_CODES=$(echo "$IDE_METADATA" | jq -r 'keys[]')
else
  # Fallback: extract IDE codes without jq
  IDE_CODES=$(echo "$IDE_METADATA" | grep -o '"[A-Z][A-Z]"' | tr -d '"' | sort -u)
fi

if [ -z "$IDE_CODES" ]; then
  echo -e "$${YELLOW}⚠️  No IDEs selected. Plugins will be installed when you launch an IDE.$${RESET}"
  exit 0
fi

echo "Selected IDEs:"
for ide_code in $IDE_CODES; do
  if command -v jq &> /dev/null; then
    ide_name=$(echo "$IDE_METADATA" | jq -r ".\"$ide_code\".name")
  else
    ide_name="$ide_code"
  fi
  echo "  - $ide_name ($ide_code)"
done
echo ""

# Function to find IDE binary path
find_ide_binary() {
  local ide_code="$1"
  local binary_name=""

  # Map IDE codes to binary names
  case "$ide_code" in
    CL) binary_name="clion" ;;
    GO) binary_name="goland" ;;
    IU) binary_name="idea" ;;
    PS) binary_name="phpstorm" ;;
    PY) binary_name="pycharm" ;;
    RD) binary_name="rider" ;;
    RM) binary_name="rubymine" ;;
    RR) binary_name="rustrover" ;;
    WS) binary_name="webstorm" ;;
    *) return 1 ;;
  esac

  # Common JetBrains installation paths
  local search_paths=(
    "$HOME/.local/share/JetBrains/Toolbox/apps/$binary_name"
    "$HOME/.cache/JetBrains/Toolbox/apps/$binary_name"
    "/opt/$binary_name/bin/$binary_name.sh"
    "/usr/local/bin/$binary_name"
    "/usr/bin/$binary_name"
  )

  # Search for the IDE binary
  for base_path in "$${search_paths[@]}"; do
    if [ -d "$base_path" ]; then
      # For Toolbox installations, find the latest version
      local latest_version=$(find "$base_path" -maxdepth 1 -type d -name "ch-*" | sort -V | tail -n 1)
      if [ -n "$latest_version" ] && [ -f "$latest_version/bin/$binary_name.sh" ]; then
        echo "$latest_version/bin/$binary_name.sh"
        return 0
      fi
    elif [ -f "$base_path" ]; then
      echo "$base_path"
      return 0
    fi
  done

  # Try to find in PATH
  if command -v "$binary_name" &> /dev/null; then
    command -v "$binary_name"
    return 0
  fi

  return 1
}

# Function to install plugins for a specific IDE
install_plugins_for_ide() {
  local ide_code="$1"
  local ide_binary="$2"
  local ide_name="$3"

  echo -e "$${BOLD}Installing plugins for $ide_name ($ide_code)...$${RESET}"

  local failed_plugins=()
  local success_count=0

  for plugin in "$${PLUGIN_LIST[@]}"; do
    if [ -z "$plugin" ]; then
      continue
    fi

    echo -n "  🔌 Installing $plugin... "

    # Run the plugin installation command
    # Note: The IDE must be closed for this to work
    if output=$("$ide_binary" installPlugins $PLUGIN_INSTALL_ARGS "$plugin" 2>&1); then
      echo -e "$${GREEN}✓$${RESET}"
      ((success_count++))
    else
      echo -e "$${RED}✗$${RESET}"
      failed_plugins+=("$plugin")
      echo "     Error: $output"
    fi
  done

  echo ""

  if [ $success_count -gt 0 ]; then
    echo -e "$${GREEN}✓ Successfully installed $success_count plugin(s) for $ide_name$${RESET}"
  fi

  if [ $${#failed_plugins[@]} -gt 0 ]; then
    echo -e "$${YELLOW}⚠️  Failed to install $${#failed_plugins[@]} plugin(s) for $ide_name:$${RESET}"
    for failed_plugin in "$${failed_plugins[@]}"; do
      echo "     - $failed_plugin"
    done
  fi

  echo ""
}

# Main installation loop
echo -e "$${BOLD}🔍 Searching for IDE installations...$${RESET}"
echo ""

installed_count=0
skipped_count=0

for ide_code in $IDE_CODES; do
  if ide_binary=$(find_ide_binary "$ide_code"); then
    if command -v jq &> /dev/null; then
      ide_name=$(echo "$IDE_METADATA" | jq -r ".\"$ide_code\".name")
    else
      ide_name="$ide_code"
    fi

    echo -e "$${GREEN}✓$${RESET} Found $ide_name: $ide_binary"
    install_plugins_for_ide "$ide_code" "$ide_binary" "$ide_name"
    ((installed_count++))
  else
    if command -v jq &> /dev/null; then
      ide_name=$(echo "$IDE_METADATA" | jq -r ".\"$ide_code\".name")
    else
      ide_name="$ide_code"
    fi
    echo -e "$${YELLOW}⚠️$${RESET}  $ide_name ($ide_code) not found - skipping"
    ((skipped_count++))
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $installed_count -eq 0 ]; then
  echo -e "$${YELLOW}⚠️  No IDE installations found.$${RESET}"
  echo "Plugins will be installed automatically when you first launch a JetBrains IDE via Toolbox."
else
  echo -e "$${GREEN}✓ Plugin installation completed for $installed_count IDE(s).$${RESET}"
  if [ $skipped_count -gt 0 ]; then
    echo -e "$${YELLOW}⚠️  Skipped $skipped_count IDE(s) (not installed yet).$${RESET}"
  fi
fi

echo ""
echo "Note: You may need to restart any running IDEs for plugins to take effect."
