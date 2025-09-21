#!/usr/bin/env bash

set -euo pipefail

# Template variables (will be replaced by Terraform templatefile function)
EXTENSIONS='${EXTENSIONS}'
SETTINGS='${SETTINGS}'
FOLDER='${FOLDER}'

# VS Code directories
EXTENSIONS_DIR="$HOME/.vscode/extensions"
CONFIG_DIR="$HOME/.config/Code/User"

# Function to log messages
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VS Code Setup] $1" >&2
}

# Function to ensure VS Code is installed
ensure_vscode() {
  if ! command -v code > /dev/null 2>&1; then
    log "VS Code CLI not found. Installing VS Code..."
    
    # Download and install VS Code
    if command -v apt-get > /dev/null 2>&1; then
      # Debian/Ubuntu
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
      sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
      sudo apt-get update > /dev/null 2>&1
      sudo apt-get install -y code > /dev/null 2>&1
    elif command -v yum > /dev/null 2>&1; then
      # RHEL/CentOS/Fedora
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
      if command -v dnf > /dev/null 2>&1; then
        sudo dnf check-update > /dev/null 2>&1 || true
        sudo dnf install -y code > /dev/null 2>&1
      else
        sudo yum check-update > /dev/null 2>&1 || true
        sudo yum install -y code > /dev/null 2>&1
      fi
    else
      log "Warning: Unsupported package manager. Please install VS Code manually."
      return 1
    fi
    
    log "VS Code installed successfully"
  else
    log "VS Code CLI is already available"
  fi
}

# Function to ensure jq is installed
ensure_jq() {
  if ! command -v jq > /dev/null 2>&1; then
    log "Installing jq for JSON processing..."
    if command -v apt-get > /dev/null 2>&1; then
      sudo apt-get update > /dev/null 2>&1
      sudo apt-get install -y jq > /dev/null 2>&1
    elif command -v yum > /dev/null 2>&1; then
      if command -v dnf > /dev/null 2>&1; then
        sudo dnf install -y jq > /dev/null 2>&1
      else
        sudo yum install -y jq > /dev/null 2>&1
      fi
    else
      log "Warning: Could not install jq. Some functionality may not work."
      return 1
    fi
  fi
}

# Function to install extensions using VS Code CLI
install_extensions() {
  if [[ -z "$EXTENSIONS" || "$EXTENSIONS" == "[]" ]]; then
    log "No extensions to install"
    return
  fi
  
  log "Installing VS Code extensions..."
  
  # Parse JSON array of extensions
  local extensions_list=$(echo "$EXTENSIONS" | jq -r '.[]' 2>/dev/null || echo "")
  
  if [[ -z "$extensions_list" ]]; then
    log "Warning: Could not parse extensions list"
    return
  fi
  
  # Install each extension using VS Code CLI
  while IFS= read -r extension; do
    if [[ -n "$extension" ]]; then
      log "Installing extension: $extension"
      if code --install-extension "$extension" --force > /dev/null 2>&1; then
        log "Successfully installed extension: $extension"
      else
        log "Warning: Failed to install extension: $extension"
      fi
    fi
  done <<< "$extensions_list"
  
  log "Extension installation completed"
}

# Function to configure settings
configure_settings() {
  if [[ -z "$SETTINGS" || "$SETTINGS" == "{}" ]]; then
    log "No settings to configure"
    return
  fi
  
  log "Configuring VS Code settings..."
  
  # Ensure config directory exists
  mkdir -p "$CONFIG_DIR"
  
  local settings_file="$CONFIG_DIR/settings.json"
  
  # If settings file doesn't exist, create it with empty object
  if [[ ! -f "$settings_file" ]]; then
    echo '{}' > "$settings_file"
  fi
  
  # Merge new settings with existing ones using jq
  local temp_settings=$(mktemp)
  if jq -s '.[0] * .[1]' "$settings_file" <(echo "$SETTINGS") > "$temp_settings" 2>/dev/null; then
    mv "$temp_settings" "$settings_file"
    log "VS Code settings configured successfully"
  else
    log "Warning: Could not merge settings, creating new settings file"
    echo "$SETTINGS" > "$settings_file"
    rm -f "$temp_settings"
  fi
}

# Function to setup VS Code workspace
setup_workspace() {
  if [[ -n "$FOLDER" ]]; then
    log "Setting up workspace for folder: $FOLDER"
    # Ensure the folder exists
    if [[ ! -d "$FOLDER" ]]; then
      log "Creating folder: $FOLDER"
      mkdir -p "$FOLDER"
    fi
  fi
}

# Main execution
main() {
  log "Starting VS Code Desktop setup..."
  
  # Ensure VS Code is installed
  if ! ensure_vscode; then
    log "Failed to ensure VS Code installation. Exiting."
    exit 1
  fi
  
  # Ensure jq is available for JSON processing
  ensure_jq
  
  # Setup workspace folder if specified
  if [[ -n "$FOLDER" ]]; then
    setup_workspace
  fi
  
  # Install extensions if specified
  if [[ -n "$EXTENSIONS" && "$EXTENSIONS" != "[]" ]]; then
    install_extensions
  fi
  
  # Configure settings if specified
  if [[ -n "$SETTINGS" && "$SETTINGS" != "{}" ]]; then
    configure_settings
  fi
  
  log "VS Code Desktop setup completed successfully!"
  log "You can now open VS Code and all extensions and settings will be available."
}

# Run main function
main "$@"