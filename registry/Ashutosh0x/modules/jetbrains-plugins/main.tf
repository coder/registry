terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "plugins" {
  type        = list(string)
  description = "List of JetBrains plugin IDs to pre-install. Find plugin IDs at https://plugins.jetbrains.com/"
  default     = []
  # Example plugin IDs:
  # - "org.jetbrains.plugins.github" (GitHub)
  # - "com.intellij.kubernetes" (Kubernetes)
  # - "org.rust.lang" (Rust)
  # - "Pythonid" (Python)
}

variable "ide_product_codes" {
  type        = list(string)
  description = "List of IDE product codes to configure plugins for. e.g. ['IU', 'PY', 'GO']"
  default     = ["IU"]
  validation {
    condition = alltrue([
      for code in var.ide_product_codes : contains(
        ["CL", "GO", "IU", "IC", "PS", "PY", "PC", "RD", "RM", "RR", "WS"], code
      )
    ])
    error_message = "Invalid product code. Valid codes: CL, GO, IU, IC, PS, PY, PC, RD, RM, RR, WS"
  }
}

variable "plugins_dir" {
  type        = string
  description = "Custom plugins directory. If empty, uses default JetBrains Toolbox location."
  default     = ""
}

variable "download_timeout" {
  type        = number
  description = "Timeout in seconds for downloading plugins."
  default     = 300
}

# Map of IDE product codes to their config directory names
locals {
  ide_config_dirs = {
    "CL" = "CLion"
    "GO" = "GoLand"
    "IU" = "IntelliJIdea"
    "IC" = "IdeaIC"
    "PS" = "PhpStorm"
    "PY" = "PyCharm"
    "PC" = "PyCharmCE"
    "RD" = "Rider"
    "RM" = "RubyMine"
    "RR" = "RustRover"
    "WS" = "WebStorm"
  }

  # Generate plugin install script
  plugins_json = jsonencode(var.plugins)
  ides_json    = jsonencode(var.ide_product_codes)
}

resource "coder_script" "jetbrains_plugins" {
  agent_id     = var.agent_id
  display_name = "JetBrains Plugin Installer"
  icon         = "/icon/jetbrains-toolbox.svg"

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== JetBrains Plugin Pre-installer ==="

    PLUGINS='${local.plugins_json}'
    IDES='${local.ides_json}'
    CUSTOM_DIR='${var.plugins_dir}'
    TIMEOUT=${var.download_timeout}

    # Check if any plugins specified
    if [ "$PLUGINS" = "[]" ] || [ -z "$PLUGINS" ]; then
      echo "No plugins specified, skipping installation."
      exit 0
    fi

    echo "Plugins to install: $PLUGINS"
    echo "Target IDEs: $IDES"

    # Determine plugins directory
    if [ -n "$CUSTOM_DIR" ]; then
      PLUGINS_BASE="$CUSTOM_DIR"
    else
      # Default JetBrains Toolbox locations
      if [ -d "$HOME/.local/share/JetBrains/Toolbox" ]; then
        PLUGINS_BASE="$HOME/.local/share/JetBrains/Toolbox/apps"
      elif [ -d "$HOME/Library/Application Support/JetBrains/Toolbox" ]; then
        PLUGINS_BASE="$HOME/Library/Application Support/JetBrains/Toolbox/apps"
      else
        # Fallback to config directory for standalone installs
        PLUGINS_BASE="$HOME/.config/JetBrains"
      fi
    fi

    echo "Plugins base directory: $PLUGINS_BASE"

    # Create IDE config directories for each target IDE
    declare -A IDE_NAMES=(
      ["CL"]="CLion"
      ["GO"]="GoLand"
      ["IU"]="IntelliJIdea"
      ["IC"]="IdeaIC"
      ["PS"]="PhpStorm"
      ["PY"]="PyCharm"
      ["PC"]="PyCharmCE"
      ["RD"]="Rider"
      ["RM"]="RubyMine"
      ["RR"]="RustRover"
      ["WS"]="WebStorm"
    )

    # Parse IDE list
    IDE_LIST=$(echo "$IDES" | tr -d '[]"' | tr ',' ' ')

    for IDE_CODE in $IDE_LIST; do
      IDE_NAME="$${IDE_NAMES[$IDE_CODE]}"
      if [ -z "$IDE_NAME" ]; then
        echo "Warning: Unknown IDE code $IDE_CODE, skipping"
        continue
      fi

      # Find or create plugins directory for this IDE
      IDE_PLUGINS_DIR="$PLUGINS_BASE/$IDE_NAME/plugins"
      mkdir -p "$IDE_PLUGINS_DIR"
      echo "Created plugins directory: $IDE_PLUGINS_DIR"

      # Parse plugin list and download each
      PLUGIN_LIST=$(echo "$PLUGINS" | tr -d '[]"' | tr ',' ' ')

      for PLUGIN_ID in $PLUGIN_LIST; do
        PLUGIN_ID=$(echo "$PLUGIN_ID" | xargs) # trim whitespace

        if [ -z "$PLUGIN_ID" ]; then
          continue
        fi

        echo "Installing plugin: $PLUGIN_ID for $IDE_NAME"

        # Check if plugin already exists
        if [ -d "$IDE_PLUGINS_DIR/$PLUGIN_ID" ]; then
          echo "  Plugin $PLUGIN_ID already installed, skipping"
          continue
        fi

        # Download plugin from JetBrains Marketplace
        PLUGIN_URL="https://plugins.jetbrains.com/pluginManager?action=download&id=$PLUGIN_ID"
        PLUGIN_ZIP="/tmp/$${PLUGIN_ID}.zip"

        echo "  Downloading from JetBrains Marketplace..."
        if curl -fsSL --max-time $TIMEOUT -o "$PLUGIN_ZIP" "$PLUGIN_URL" 2>/dev/null; then
          # Extract plugin
          if unzip -q -o "$PLUGIN_ZIP" -d "$IDE_PLUGINS_DIR" 2>/dev/null; then
            echo "  ✓ Plugin $PLUGIN_ID installed successfully"
          else
            echo "  ⚠ Failed to extract plugin $PLUGIN_ID"
          fi
          rm -f "$PLUGIN_ZIP"
        else
          echo "  ⚠ Failed to download plugin $PLUGIN_ID"
        fi
      done
    done

    echo "=== Plugin installation complete ==="
  EOT

  run_on_start = true
}

output "installed_plugins" {
  description = "List of plugins configured for installation"
  value       = var.plugins
}

output "target_ides" {
  description = "List of IDEs configured for plugin installation"
  value       = var.ide_product_codes
}
