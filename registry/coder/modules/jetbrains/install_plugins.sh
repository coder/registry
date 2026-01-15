#!/usr/bin/env bash

# JetBrains Plugin Pre-installation Script
# This script handles plugin installation for JetBrains IDEs in Coder workspaces

PLUGINS="${PLUGINS}"
PROJECT_DIR="${PROJECT_DIR}"

BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

IDE_CACHE_DIR="$HOME/.cache/JetBrains/RemoteDev/dist"
PLUGIN_INSTALL_LOG="/tmp/jetbrains-plugin-install.log"

# Exit early if no plugins specified
if [ -z "$PLUGINS" ]; then
  echo "No plugins specified, skipping plugin setup."
  exit 0
fi

echo -e "$${BOLD}🔌 Setting up JetBrains plugins...$${RESET}"

# Step 1: Create .idea/externalDependencies.xml
# This ensures users are prompted to install required plugins when opening the project
setup_external_dependencies() {
  if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "$${YELLOW}⚠️  Project directory $PROJECT_DIR does not exist yet, skipping externalDependencies.xml$${RESET}"
    return
  fi

  mkdir -p "$PROJECT_DIR/.idea"

  echo -e "📦 Creating plugin requirements file..."

  cat > "$PROJECT_DIR/.idea/externalDependencies.xml" << 'XMLHEADER'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ExternalDependencies">
XMLHEADER

  IFS=',' read -r -a PLUGIN_ARRAY <<< "$PLUGINS"
  for plugin in "$${PLUGIN_ARRAY[@]}"; do
    plugin=$(echo "$plugin" | xargs) # trim whitespace
    if [ -n "$plugin" ]; then
      echo "    <plugin id=\"$plugin\" />" >> "$PROJECT_DIR/.idea/externalDependencies.xml"
    fi
  done

  cat >> "$PROJECT_DIR/.idea/externalDependencies.xml" << 'XMLFOOTER'
  </component>
</project>
XMLFOOTER

  echo -e "$${GREEN}✅ Created $PROJECT_DIR/.idea/externalDependencies.xml$${RESET}"
  echo "   When you open this project, JetBrains IDE will prompt you to install the required plugins."
}

# Step 2: Background plugin installer
# Monitors for IDE installation and installs plugins automatically
install_plugins_background() {
  echo -e "🔄 Starting background plugin installer..."

  # Run in background subshell
  (
    exec > "$PLUGIN_INSTALL_LOG" 2>&1

    MAX_WAIT=7200 # Wait up to 2 hours for IDE to be installed
    INTERVAL=30   # Check every 30 seconds
    WAITED=0

    echo "[$(date)] Background plugin installer started"
    echo "[$(date)] Watching for IDE installation in $IDE_CACHE_DIR"
    echo "[$(date)] Plugins to install: $PLUGINS"

    while [ $WAITED -lt $MAX_WAIT ]; do
      # Look for any installed IDE's remote-dev-server.sh
      if [ -d "$IDE_CACHE_DIR" ]; then
        IDE_SCRIPT=$(find "$IDE_CACHE_DIR" -name "remote-dev-server.sh" -type f 2> /dev/null | head -1)

        if [ -n "$IDE_SCRIPT" ] && [ -x "$IDE_SCRIPT" ]; then
          echo "[$(date)] Found IDE at: $IDE_SCRIPT"

          # Get the IDE's bin directory
          IDE_BIN_DIR=$(dirname "$IDE_SCRIPT")

          # Wait a moment for IDE to fully initialize
          sleep 5

          # Install each plugin
          IFS=',' read -r -a PLUGIN_ARRAY <<< "$PLUGINS"
          INSTALL_SUCCESS=true

          for plugin in "$${PLUGIN_ARRAY[@]}"; do
            plugin=$(echo "$plugin" | xargs) # trim whitespace
            if [ -n "$plugin" ]; then
              echo "[$(date)] Installing plugin: $plugin"

              # Try using remote-dev-server.sh first
              if "$IDE_SCRIPT" installPlugins "$PROJECT_DIR" "$plugin" 2>&1; then
                echo "[$(date)] Successfully installed: $plugin"
              else
                echo "[$(date)] Failed to install via remote-dev-server.sh, trying alternative methods..."

                # Try finding IDE-specific launcher (idea.sh, pycharm.sh, etc.)
                for launcher in "$IDE_BIN_DIR"/*.sh; do
                  if [[ "$launcher" != *"remote-dev"* ]] && [ -x "$launcher" ]; then
                    echo "[$(date)] Trying launcher: $launcher"
                    if "$launcher" installPlugins "$plugin" 2>&1; then
                      echo "[$(date)] Successfully installed via $launcher: $plugin"
                      break
                    fi
                  fi
                done
              fi
            fi
          done

          echo "[$(date)] Plugin installation process completed!"
          exit 0
        fi
      fi

      sleep $INTERVAL
      WAITED=$((WAITED + INTERVAL))
    done

    echo "[$(date)] Timed out waiting for IDE installation after $MAX_WAIT seconds"
  ) &

  local BG_PID=$!
  echo -e "📋 Background installer running (PID: $BG_PID)"
  echo -e "   Log file: $PLUGIN_INSTALL_LOG"

  # Save PID for potential cleanup
  echo "$BG_PID" > /tmp/jetbrains-plugin-installer.pid
}

# Main execution
setup_external_dependencies
install_plugins_background

echo -e "$${GREEN}🎉 JetBrains plugin setup complete!$${RESET}"
echo ""
echo "Plugins will be installed automatically when JetBrains IDE is detected."
echo "You can also install them manually via the IDE's plugin manager."
