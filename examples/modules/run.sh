#!/usr/bin/env bash

# These variables are injected via Terraform's templatefile
LOG_PATH="${LOG_PATH}"
PLUGINS="${PLUGINS}"

echo "Starting JetBrains plugin installation..." >> "$LOG_PATH"

# Check if the PLUGINS list is not empty
if [ -n "$PLUGINS" ]; then
    # Standard JetBrains directory for Remote Development plugins
    PLUGIN_DIR="$HOME/.local/share/JetBrains/plugins"
    mkdir -p "$PLUGIN_DIR"

    for plugin_id in $PLUGINS; do
        echo "Installing plugin: $plugin_id" >> "$LOG_PATH"
        
        # Fetch the latest download URL from JetBrains Marketplace API
        # Using grep to extract the 'downloadUrl' field from the JSON response
        DOWNLOAD_PATH=$(curl -s "https://plugins.jetbrains.com/api/plugins/$plugin_id/updates?size=1" | grep -oP '(?<="downloadUrl":")[^"]+')
        
        # Only proceed if a valid download path was found
        if [ -n "$DOWNLOAD_PATH" ]; then
            echo "Downloading $plugin_id..." >> "$LOG_PATH"
            
            # Download the plugin zip file to a temporary location
            curl -L "https://plugins.jetbrains.com$DOWNLOAD_PATH" -o "/tmp/$plugin_id.zip"
            
            # Extract the plugin to the JetBrains plugins directory
            # -o flag overwrites existing files if any
            unzip -o "/tmp/$plugin_id.zip" -d "$PLUGIN_DIR"
            
            # Clean up the temporary zip file
            rm "/tmp/$plugin_id.zip"
            echo "Successfully installed $plugin_id" >> "$LOG_PATH"
        else
            echo "Error: Could not find download path for $plugin_id" >> "$LOG_PATH"
        fi
    done
fi