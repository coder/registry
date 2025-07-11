#!/bin/bash
set -euo pipefail

# VS Code Desktop Extension and Settings Setup Script
# This script installs VS Code extensions and configures workspace settings

EXTENSIONS='${EXTENSIONS}'
SETTINGS='${SETTINGS}'
FOLDER='${FOLDER}'

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if VS Code CLI is available
check_vscode_cli() {
    if command -v code >/dev/null 2>&1; then
        return 0
    fi
    
    # Try alternative paths where VS Code might be installed
    local vscode_paths=(
        "/usr/bin/code"
        "/usr/local/bin/code"
        "/opt/visual-studio-code/bin/code"
        "$HOME/.local/bin/code"
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    )
    
    for path in "$${vscode_paths[@]}"; do
        if [ -x "$path" ]; then
            export PATH="$PATH:$(dirname "$path")"
            return 0
        fi
    done
    
    return 1
}

# Function to install VS Code extensions
install_extensions() {
    local extensions_json="$1"
    
    if [ "$extensions_json" = "[]" ] || [ "$extensions_json" = "null" ]; then
        log "No extensions to install"
        return 0
    fi
    
    log "Installing VS Code extensions..."
    
    # Parse extensions from JSON array
    local extensions
    extensions=$(echo "$extensions_json" | jq -r '.[]' 2>/dev/null || echo "")
    
    if [ -z "$extensions" ]; then
        log "No valid extensions found in configuration"
        return 0
    fi
    
    local failed_extensions=()
    local successful_extensions=()
    local total_extensions=0
    
    # Count total extensions first
    while IFS= read -r extension; do
        if [ -n "$extension" ]; then
            ((total_extensions++))
        fi
    done <<< "$extensions"
    
    log "Found $total_extensions extensions to install"
    
    # Install extensions with progress tracking
    local current=0
    while IFS= read -r extension; do
        if [ -n "$extension" ]; then
            ((current++))
            log "Installing extension ($current/$total_extensions): $extension"
            
            # Validate extension format before attempting installation
            if [[ ! "$extension" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
                log "WARNING: Invalid extension format: $extension (skipping)"
                failed_extensions+=("$extension")
                continue
            fi
            
            if timeout 30 code --install-extension "$extension" --force >/dev/null 2>&1; then
                successful_extensions+=("$extension")
                log "✓ Successfully installed: $extension"
            else
                failed_extensions+=("$extension")
                log "✗ Failed to install: $extension"
            fi
        fi
    done <<< "$extensions"
    
    # Report results
    if [ $${#successful_extensions[@]} -gt 0 ]; then
        log "Successfully installed $${#successful_extensions[@]} extensions: $${successful_extensions[*]}"
    fi
    
    if [ $${#failed_extensions[@]} -gt 0 ]; then
        log "WARNING: Failed to install $${#failed_extensions[@]} extensions: $${failed_extensions[*]}"
    fi
}

# Function to configure workspace settings
configure_settings() {
    local settings_json="$1"
    local folder_path="$2"
    
    if [ "$settings_json" = "{}" ] || [ "$settings_json" = "null" ]; then
        log "No settings to configure"
        return 0
    fi
    
    log "Configuring VS Code workspace settings..."
    
    # Determine the workspace directory
    local workspace_dir
    if [ -n "$folder_path" ] && [ -d "$folder_path" ]; then
        workspace_dir="$folder_path"
    else
        workspace_dir="$(pwd)"
    fi
    
    # Create .vscode directory if it doesn't exist
    local vscode_dir="$workspace_dir/.vscode"
    mkdir -p "$vscode_dir"
    
    # Path to settings.json
    local settings_file="$vscode_dir/settings.json"
    
    # Merge with existing settings if they exist
    local final_settings
    if [ -f "$settings_file" ]; then
        log "Merging with existing settings in $settings_file"
        # Merge existing settings with new settings, giving priority to new settings
        final_settings=$(jq -s '.[0] * .[1]' "$settings_file" <(echo "$settings_json") 2>/dev/null || echo "$settings_json")
    else
        final_settings="$settings_json"
    fi
    
    # Write settings to file with proper formatting
    if echo "$final_settings" | jq empty 2>/dev/null; then
        echo "$final_settings" | jq --indent 2 '.' > "$settings_file"
        
        if [ $? -eq 0 ]; then
            log "Successfully configured workspace settings in $settings_file"
            # Log the settings that were applied (first 3 keys for brevity)
            local setting_keys
            setting_keys=$(echo "$final_settings" | jq -r 'keys[0:3] | join(", ")' 2>/dev/null || echo "")
            if [ -n "$setting_keys" ]; then
                log "Applied settings: $setting_keys$(echo "$final_settings" | jq -r 'if (keys | length) > 3 then " and " + ((keys | length) - 3 | tostring) + " more" else "" end' 2>/dev/null || echo "")"
            fi
        else
            log "ERROR: Failed to write settings to $settings_file"
            return 1
        fi
    else
        log "ERROR: Invalid JSON format in settings"
        return 1
    fi
}

# Function to create recommended extensions file
create_extensions_recommendations() {
    local extensions_json="$1"
    local folder_path="$2"
    
    if [ "$extensions_json" = "[]" ] || [ "$extensions_json" = "null" ]; then
        return 0
    fi
    
    # Determine the workspace directory
    local workspace_dir
    if [ -n "$folder_path" ] && [ -d "$folder_path" ]; then
        workspace_dir="$folder_path"
    else
        workspace_dir="$(pwd)"
    fi
    
    # Create .vscode directory if it doesn't exist
    local vscode_dir="$workspace_dir/.vscode"
    mkdir -p "$vscode_dir"
    
    # Create extensions.json with recommendations
    local extensions_file="$vscode_dir/extensions.json"
    local recommendations
    
    # Create recommendations with proper formatting
    recommendations=$(echo "$extensions_json" | jq '{
        recommendations: .,
        unwantedRecommendations: []
    }' 2>/dev/null || echo '{"recommendations":[], "unwantedRecommendations":[]}')
    
    echo "$recommendations" | jq --indent 2 '.' > "$extensions_file"
    
    if [ $? -eq 0 ]; then
        local ext_count
        ext_count=$(echo "$extensions_json" | jq 'length' 2>/dev/null || echo "0")
        log "Created extensions recommendations in $extensions_file ($ext_count extensions)"
    else
        log "WARNING: Failed to create extensions recommendations file"
    fi
}

# Main execution
main() {
    log "Starting VS Code Desktop setup..."
    
    # Check if jq is available for JSON parsing
    if ! command -v jq >/dev/null 2>&1; then
        log "jq is not installed. Attempting installation..."
        
        # Try to install jq on common distributions (with error suppression)
        if command -v apt-get >/dev/null 2>&1; then
            log "Attempting to install jq via apt-get..."
            sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y jq >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            log "Attempting to install jq via yum..."
            sudo yum install -y jq >/dev/null 2>&1
        elif command -v pacman >/dev/null 2>&1; then
            log "Attempting to install jq via pacman..."
            sudo pacman -S --noconfirm jq >/dev/null 2>&1
        elif command -v brew >/dev/null 2>&1; then
            log "Attempting to install jq via brew..."
            brew install jq >/dev/null 2>&1
        fi
        
        # Final check
        if ! command -v jq >/dev/null 2>&1; then
            log "ERROR: jq installation failed. Cannot process JSON configuration."
            log "Please install jq manually: https://stedolan.github.io/jq/download/"
            exit 1
        else
            log "✓ jq installed successfully"
        fi
    fi
    
    # Check if VS Code CLI is available
    if ! check_vscode_cli; then
        log "WARNING: VS Code CLI (code command) is not available in PATH."
        log "Extensions cannot be installed automatically, but settings will still be configured."
        log "To install extensions manually, ensure VS Code is installed and the 'code' command is available."
        
        # Still configure settings and create recommendations
        configure_settings "$SETTINGS" "$FOLDER"
        create_extensions_recommendations "$EXTENSIONS" "$FOLDER"
        return 0
    fi
    
    # Install extensions
    install_extensions "$EXTENSIONS"
    
    # Configure settings
    configure_settings "$SETTINGS" "$FOLDER"
    
    # Create extensions recommendations file
    create_extensions_recommendations "$EXTENSIONS" "$FOLDER"
    
    log "VS Code Desktop setup completed successfully!"
}

# Run main function
main "$@"
