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

# Function to ensure VS Code CLI is installed (minimal installation)
ensure_vscode_cli() {
  if ! command -v code > /dev/null 2>&1; then
    log "VS Code CLI not found. Installing VS Code CLI..."
    
    # Create temporary directory for installation
    local temp_dir=$$(mktemp -d)
    cd "$${temp_dir}"
    
    # Detect architecture
    local arch=$$(uname -m)
    local vscode_arch
    case "$${arch}" in
      x86_64) vscode_arch="x64" ;;
      aarch64|arm64) vscode_arch="arm64" ;;
      armv7l) vscode_arch="armhf" ;;
      *) 
        log "Error: Unsupported architecture: $${arch}"
        exit 1
        ;;
    esac
    
    # Download VS Code CLI
    local cli_url="https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-$${vscode_arch}"
    log "Downloading VS Code CLI from: $${cli_url}"
    
    # Install curl if not available
    if ! command -v curl > /dev/null 2>&1; then
      log "Installing curl..."
      if command -v apt-get > /dev/null 2>&1; then
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y curl > /dev/null 2>&1
      elif command -v yum > /dev/null 2>&1; then
        sudo yum install -y curl > /dev/null 2>&1
      elif command -v dnf > /dev/null 2>&1; then
        sudo dnf install -y curl > /dev/null 2>&1
      else
        log "Error: Cannot install curl. Please install curl manually."
        exit 1
      fi
    fi
    
    # Download and extract CLI
    curl -L "$${cli_url}" -o vscode-cli.tar.gz
    tar -xzf vscode-cli.tar.gz
    sudo mv code /usr/local/bin/code
    sudo chmod +x /usr/local/bin/code
    
    # Clean up
    cd /
    rm -rf "$${temp_dir}"
    
    log "VS Code CLI installed successfully"
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

# Function to validate extension format
validate_extension() {
  local ext="$${1}"
  if [[ ! "$${ext}" =~ ^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$$ ]]; then
    log "Warning: Invalid extension format: $${ext} (expected: publisher.extension-name)"
    return 1
  fi
  return 0
}

# Function to install extensions using VS Code CLI with extensions directory
install_extensions() {
  if [[ -z "$EXTENSIONS" || "$EXTENSIONS" == "[]" ]]; then
    log "No extensions to install"
    return
  fi
  
  log "Installing VS Code extensions to extensions directory..."
  
  # Create extensions directory
  mkdir -p "$EXTENSIONS_DIR"
  
  # Parse JSON array of extensions
  local extensions_list=$$(echo "$${EXTENSIONS}" | jq -r '.[]' 2>/dev/null || echo "")
  
  if [[ -z "$${extensions_list}" ]]; then
    log "Warning: Could not parse extensions list"
    return
  fi
  
  # Install each extension using VS Code CLI with specified extensions directory
  while IFS= read -r extension; do
    if [[ -n "$${extension}" ]]; then
      if validate_extension "$${extension}"; then
        log "Installing extension: $${extension}"
        # Use --extensions-dir to specify where extensions are installed
        if code --extensions-dir "$${EXTENSIONS_DIR}" --install-extension "$${extension}" --force > /dev/null 2>&1; then
          log "Successfully installed extension: $${extension}"
        else
          log "Warning: Failed to install extension: $${extension}"
        fi
      fi
    fi
  done <<< "$${extensions_list}"
  
  log "Extension installation completed. Extensions installed in: $${EXTENSIONS_DIR}"
}

# Function to configure settings
configure_settings() {
  if [[ -z "$SETTINGS" || "$SETTINGS" == "{}" ]]; then
    log "No settings to configure"
    return
  fi
  
  log "Configuring VS Code settings..."
  
  # Determine settings file path
  local settings_dir
  local settings_file
  
  if [[ -n "$${FOLDER}" && "$${FOLDER}" != "" ]]; then
    # Workspace-specific settings
    settings_dir="$${FOLDER}/.vscode"
    settings_file="$${settings_dir}/settings.json"
    log "Using workspace settings: $${settings_file}"
  else
    # Global user settings
    settings_dir="$${CONFIG_DIR}"
    settings_file="$${CONFIG_DIR}/settings.json"
    log "Using global settings: $${settings_file}"
  fi
  
  # Ensure settings directory exists
  mkdir -p "$${settings_dir}"
  
  # If settings file doesn't exist, create it with empty object
  if [[ ! -f "$${settings_file}" ]]; then
    echo '{}' > "$${settings_file}"
  fi
  
  # Merge new settings with existing ones using jq
  local temp_settings=$$(mktemp)
  if jq -s '.[0] * .[1]' "$${settings_file}" <(echo "$${SETTINGS}") > "$${temp_settings}" 2>/dev/null; then
    mv "$${temp_settings}" "$${settings_file}"
    log "VS Code settings configured successfully"
  else
    log "Warning: Could not merge settings, creating new settings file"
    echo "$${SETTINGS}" > "$${settings_file}"
    rm -f "$${temp_settings}"
  fi
}

# Function to setup VS Code workspace
setup_workspace() {
  if [[ -n "$${FOLDER}" ]]; then
    log "Setting up workspace for folder: $${FOLDER}"
    # Ensure the folder exists
    if [[ ! -d "$${FOLDER}" ]]; then
      log "Creating folder: $${FOLDER}"
      mkdir -p "$${FOLDER}"
    fi
  fi
}

# Main execution
main() {
  log "Starting VS Code Desktop setup with CLI-only installation..."
  
  # Ensure VS Code CLI is installed (minimal installation)
  if ! ensure_vscode_cli; then
    log "Failed to ensure VS Code CLI installation. Exiting."
    exit 1
  fi
  
  # Ensure jq is available for JSON processing
  ensure_jq
  
  # Setup workspace folder if specified
  if [[ -n "$${FOLDER}" ]]; then
    setup_workspace
  fi
  
  # Install extensions using CLI with extensions directory if specified
  if [[ -n "$${EXTENSIONS}" && "$${EXTENSIONS}" != "[]" ]]; then
    install_extensions
  fi
  
  # Configure settings if specified
  if [[ -n "$${SETTINGS}" && "$${SETTINGS}" != "{}" ]]; then
    configure_settings
  fi
  
  log "VS Code Desktop setup completed successfully!"
  log "Extensions installed in: $${EXTENSIONS_DIR}"
  log "This setup works with VS Code-based IDEs (Code, Cursor, WindSurf, Kiro, etc.)"
}

# Run main function
main "$@"