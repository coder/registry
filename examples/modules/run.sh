#!/usr/bin/env bash

# These variables are injected via Terraform's templatefile
LOG_PATH="${LOG_PATH}"
PLUGINS="${PLUGINS}"

echo "Starting JetBrains plugin installation..." >> "$LOG_PATH"

if [ -n "$PLUGINS" ]; then
    PLUGIN_DIR="$HOME/.local/share/JetBrains/plugins"
    mkdir -p "$PLUGIN_DIR"

    for plugin_id in $PLUGINS; do
        echo "Installing plugin: $plugin_id" >> "$LOG_PATH"
        
        # 1. FIXED: Using sed instead of grep -P for better compatibility
        JSON_RESPONSE=$(curl -s "https://plugins.jetbrains.com/api/plugins/$plugin_id/updates?size=1")
        DOWNLOAD_PATH=$(echo "$JSON_RESPONSE" | sed -n 's/.*"downloadUrl":"\([^"]*\)".*/\1/p')
        
        if [ -n "$DOWNLOAD_PATH" ]; then
            echo "Downloading $plugin_id..." >> "$LOG_PATH"
            
            # 2. FIXED: Checking if download and unzip actually work
            if curl -L "https://plugins.jetbrains.com$DOWNLOAD_PATH" -o "/tmp/$plugin_id.zip" && \
               unzip -o "/tmp/$plugin_id.zip" -d "$PLUGIN_DIR"; then
                
                rm "/tmp/$plugin_id.zip"
                echo "Successfully installed $plugin_id" >> "$LOG_PATH"
            else
                echo "Error: Failed to download or extract $plugin_id" >> "$LOG_PATH"
                # Optional: exit 1 (agar aap chahte ho ki script yahi ruk jaye)
            fi
        else
            echo "Error: Could not find download path for $plugin_id" >> "$LOG_PATH"
        fi
    done
fi
