#!/bin/bash

set -euo pipefail

# VS Code Setup Script for Coder Workspaces
# This script installs VS Code extensions and applies settings

VSCODE_USER_DIR="$HOME/.vscode-server"
EXTENSIONS_DIR="$VSCODE_USER_DIR/extensions"
SETTINGS_DIR="$VSCODE_USER_DIR/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# Ensure VS Code server directories exist
mkdir -p "$EXTENSIONS_DIR"
mkdir -p "$SETTINGS_DIR"

echo "🚀 Starting VS Code setup..."

# Function to install VS Code extensions
install_extensions() {
    %{ for extension in extensions ~}
    local extension="${extension}"
    if [ -n "$extension" ]; then
        echo "� Installing extension: $extension"
        install_single_extension "$extension"
    fi
    %{ endfor ~}
}
    %{ endfor ~}
}

# Function to install a single extension
install_single_extension() {
    local extension="$1"
    
    # Check if code command is available
    if ! command -v code &> /dev/null; then
        echo "⚠️  VS Code CLI not found. Installing extensions manually..."
        
        # Download and install VS Code CLI if not available
        if command -v curl &> /dev/null; then
            echo "📥 Downloading VS Code CLI..."
            curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz
            tar -xf vscode_cli.tar.gz
            chmod +x code
            sudo mv code /usr/local/bin/ 2>/dev/null || mv code /tmp/code
            export PATH="/tmp:$PATH"
        else
            echo "❌ curl not available. Cannot install VS Code CLI."
            return 1
        fi
    fi
    
    echo "🔧 Installing extension: $extension"
    code --install-extension "$extension" --force || {
        echo "⚠️  Failed to install extension: $extension"
        return 1
    }
    echo "✅ Installed: $extension"
}
}

# Function to apply VS Code settings
apply_settings() {
    local settings='${settings}'
    
    if [ "$settings" = "{}" ] || [ -z "$settings" ]; then
        echo "⚙️  No custom settings to apply"
        return 0
    fi
    
    echo "⚙️  Applying VS Code settings..."
    
    # Create settings file if it doesn't exist
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "{}" > "$SETTINGS_FILE"
    fi
    
    # Merge settings using jq if available, otherwise overwrite
    if command -v jq &> /dev/null; then
        echo "🔄 Merging settings with existing configuration..."
        local temp_file=$(mktemp)
        jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$settings") > "$temp_file"
        mv "$temp_file" "$SETTINGS_FILE"
    else
        echo "⚠️  jq not available. Overwriting existing settings..."
        echo "$settings" > "$SETTINGS_FILE"
    fi
    
    echo "✅ Settings applied successfully"
}

# Function to set up workspace configuration
setup_workspace_config() {
    local workspace_dir="${1:-$PWD}"
    local vscode_dir="$workspace_dir/.vscode"
    
    echo "📁 Setting up workspace configuration in: $workspace_dir"
    
    if [ ! -d "$vscode_dir" ]; then
        mkdir -p "$vscode_dir"
        echo "📂 Created .vscode directory"
    fi
    
    # Create extensions.json with recommended extensions
    cat > "$vscode_dir/extensions.json" << 'EOF'
{
    "recommendations": [
%{ for extension in extensions ~}
        "${extension}"%{ if extension != extensions[length(extensions)-1] },%{ endif }
%{ endfor ~}
    ]
}
EOF
    echo "📋 Created extensions.json with recommendations"
}

# Main execution
main() {
    echo "🎯 VS Code Enhanced Setup"
    echo "=========================="
    
    # Install extensions
    install_extensions
    
    # Apply settings
    apply_settings
    
    # Setup workspace configuration
    setup_workspace_config
    
    echo "🎉 VS Code setup completed successfully!"
    echo "💡 Extensions and settings will be available when you connect with VS Code Desktop"
}

# Run main function
main "$@"
