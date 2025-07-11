#!/bin/bash
set -euo pipefail

# Colors for output
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

# Plugin list from terraform variable (passed as JSON array)
PLUGINS_JSON='${plugins}'

echo -e "$${BOLD}🔌 JetBrains Plugin Installer$${RESET}"

# Exit early if no plugins specified
if [ "$PLUGINS_JSON" = "[]" ] || [ "$PLUGINS_JSON" = "" ] || [ "$PLUGINS_JSON" = "null" ]; then
    echo -e "$${YELLOW}No plugins specified for installation.$${RESET}"
    exit 0
fi

# Parse plugin list from JSON array
# Convert JSON array like ["plugin1", "plugin2"] to space-separated list
PLUGIN_IDS=$(echo "$PLUGINS_JSON" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | sed 's/,/ /g' | xargs)

if [ -z "$PLUGIN_IDS" ]; then
    echo -e "$${YELLOW}No valid plugins found in the list.$${RESET}"
    exit 0
fi

echo -e "$${BOLD}Plugins to install:$${RESET}"
for plugin in $PLUGIN_IDS; do
    echo "  - $plugin"
done

# JetBrains Gateway backend installation directory
JETBRAINS_BACKEND_DIR="$HOME/.cache/JetBrains/RemoteDev/dist"

# Function to wait for IDE installation
wait_for_ide_installation() {
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=10

    echo -e "$${BOLD}Waiting for JetBrains IDE backend installation...$${RESET}"
    
    while [ $wait_time -lt $max_wait ]; do
        if [ -d "$JETBRAINS_BACKEND_DIR" ] && [ "$(ls -A $JETBRAINS_BACKEND_DIR 2>/dev/null | wc -l)" -gt 0 ]; then
            # Check if any IDE directory contains remote-dev-server.sh
            for ide_dir in "$JETBRAINS_BACKEND_DIR"/*; do
                if [ -d "$ide_dir" ] && [ -f "$ide_dir/bin/remote-dev-server.sh" ]; then
                    echo -e "$${GREEN}✓ Found IDE installation at: $ide_dir$${RESET}"
                    return 0
                fi
            done
        fi
        
        echo "  Waiting for IDE installation... ($wait_time/$max_wait seconds)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    echo -e "$${RED}✗ Timeout waiting for IDE installation after $max_wait seconds$${RESET}"
    return 1
}

# Function to find remote-dev-server.sh script
find_remote_dev_server() {
    # Look in the standard Gateway installation directory
    if [ -d "$JETBRAINS_BACKEND_DIR" ]; then
        for ide_dir in "$JETBRAINS_BACKEND_DIR"/*; do
            if [ -d "$ide_dir" ] && [ -f "$ide_dir/bin/remote-dev-server.sh" ]; then
                echo "$ide_dir/bin/remote-dev-server.sh"
                return 0
            fi
        done
    fi
    
    # Fallback: search in common locations
    local search_paths=(
        "/opt/idea-*/bin/remote-dev-server.sh"
        "/opt/jetbrains/*/bin/remote-dev-server.sh" 
        "$HOME/*/bin/remote-dev-server.sh"
    )
    
    for path_pattern in "$${search_paths[@]}"; do
        for script in $path_pattern; do
            if [ -f "$script" ]; then
                echo "$script"
                return 0
            fi
        done
    done
    
    # Last resort: check if it's in PATH
    if command -v remote-dev-server.sh >/dev/null 2>&1; then
        echo "remote-dev-server.sh"
        return 0
    fi
    
    return 1
}

# Function to install plugins using remote-dev-server.sh
install_plugins() {
    local remote_dev_server="$1"
    local success_count=0
    local total_count=0
    
    echo -e "$${BOLD}Installing plugins using JetBrains remote-dev-server...$${RESET}"
    echo "  Using remote-dev-server: $remote_dev_server"
    
    for plugin in $PLUGIN_IDS; do
        plugin=$(echo "$plugin" | xargs)  # Trim whitespace
        if [ -n "$plugin" ]; then
            total_count=$((total_count + 1))
            echo "    Installing plugin: $plugin"
            
            # Use remote-dev-server.sh installPlugins command
            # Note: This requires a project path, we'll use current directory or home
            local project_path="$PWD"
            if [ ! -d "$project_path/.git" ] && [ ! -d "$project_path/.idea" ]; then
                project_path="$HOME"
            fi
            
            if timeout 120s "$remote_dev_server" installPlugins "$project_path" "$plugin" >/dev/null 2>&1; then
                echo -e "      $${GREEN}✓ Successfully installed $plugin$${RESET}"
                success_count=$((success_count + 1))
            else
                echo -e "      $${YELLOW}⚠ Failed to install $plugin (may already be installed or unavailable)$${RESET}"
            fi
        fi
    done
    
    echo -e "$${BOLD}  Plugin installation summary: $success_count/$total_count successful$${RESET}"
    return 0
}

# Main execution
main() {
    # Wait for IDE installation (only in remote environment)
    if [ -n "$${CODER_AGENT_TOKEN:-}" ] || [ -n "$${REMOTE_CONTAINERS:-}" ]; then
        if ! wait_for_ide_installation; then
            echo -e "$${YELLOW}💡 IDE not yet installed by Gateway. Plugins will be installed when IDE becomes available.$${RESET}"
            # In a real deployment, we might want to retry later or use a different approach
        fi
    else
        echo -e "$${YELLOW}⚠ Running outside Coder environment - skipping IDE installation wait$${RESET}"
    fi
    
    # Find remote-dev-server.sh
    local remote_dev_server
    if remote_dev_server=$(find_remote_dev_server); then
        echo -e "$${GREEN}✓ Found remote-dev-server script$${RESET}"
        install_plugins "$remote_dev_server"
    else
        echo -e "$${RED}✗ Could not find remote-dev-server.sh script$${RESET}"
        echo -e "$${YELLOW}💡 This may be normal if JetBrains Gateway hasn't downloaded the IDE yet.$${RESET}"
        echo -e "$${YELLOW}💡 Plugins can be installed manually later using the IDE's plugin manager.$${RESET}"
        exit 1
    fi
    
    echo -e "$${GREEN}🎉 Plugin installation process completed!$${RESET}"
    echo -e "$${BOLD}Note: Plugins will be available in your IDE after the next connection.$${RESET}"
}

# Run main function
main "$@" 