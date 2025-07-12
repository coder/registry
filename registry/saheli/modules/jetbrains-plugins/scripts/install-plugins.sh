#!/usr/bin/env bash

set -euo pipefail

# Template variables from Terraform
PLUGINS=(${join(" ", plugins)})
SELECTED_IDES=(${join(" ", selected_ides)})
FOLDER="${folder}"

# IDE configuration directory mapping
declare -A IDE_CONFIG_DIRS
IDE_CONFIG_DIRS["CL"]="CLion"
IDE_CONFIG_DIRS["GO"]="GoLand"  
IDE_CONFIG_DIRS["IU"]="IntelliJIdea"
IDE_CONFIG_DIRS["PS"]="PhpStorm"
IDE_CONFIG_DIRS["PY"]="PyCharm"
IDE_CONFIG_DIRS["RD"]="Rider"
IDE_CONFIG_DIRS["RM"]="RubyMine"
IDE_CONFIG_DIRS["RR"]="RustRover"
IDE_CONFIG_DIRS["WS"]="WebStorm"

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Function to create plugin configuration for an IDE
create_plugin_config() {
    local ide_code="$1"
    local config_dir="$${IDE_CONFIG_DIRS[$ide_code]}"
    
    # JetBrains configuration path (standard location)
    local jetbrains_config="$HOME/.config/JetBrains"
    
    echo -e "$${BOLD}🔧 Configuring plugins for $config_dir...$${RESET}"
    
    # Find the latest version directory or create a generic one
    local ide_config_dir
    if [ -d "$jetbrains_config" ]; then
        # Look for existing configuration directory
        ide_config_dir=$(find "$jetbrains_config" -maxdepth 1 -name "$config_dir*" -type d | head -1)
        
        if [ -z "$ide_config_dir" ]; then
            # Create a generic configuration directory
            ide_config_dir="$jetbrains_config/$${config_dir}2025.1"
            mkdir -p "$ide_config_dir"
        fi
    else
        # Create the base configuration structure
        mkdir -p "$jetbrains_config"
        ide_config_dir="$jetbrains_config/$${config_dir}2025.1"
        mkdir -p "$ide_config_dir"
    fi
    
    echo -e "  📁 Using config directory: $${BLUE}$ide_config_dir$${RESET}"
    
    # Create the plugins configuration
    local plugins_config="$ide_config_dir/disabled_plugins.txt"
    local enabled_plugins="$ide_config_dir/enabled_plugins.txt"
    
    # Ensure plugins directory exists
    mkdir -p "$ide_config_dir/plugins"
    
    # Create a list of enabled plugins (so they auto-install when IDE starts)
    echo -e "  📝 Creating plugin configuration..."
    
    # Write enabled plugins list
    for plugin_id in "$${PLUGINS[@]}"; do
        if [ -n "$plugin_id" ]; then
            echo "$plugin_id" >> "$enabled_plugins"
            echo -e "    ✅ Configured for auto-install: $${GREEN}$plugin_id$${RESET}"
        fi
    done
    
    # Create IDE-specific configuration that will trigger plugin installation
    local ide_options="$ide_config_dir/options"
    mkdir -p "$ide_options"
    
    # Create plugin manager configuration
    cat > "$ide_options/pluginAdvertiser.xml" <<EOF
<application>
  <component name="PluginFeatureService">
    <option name="features">
      <map>
$(for plugin_id in "$${PLUGINS[@]}"; do
    if [ -n "$plugin_id" ]; then
        echo "        <entry key=\"$plugin_id\" value=\"true\" />"
    fi
done)
      </map>
    </option>
  </component>
</application>
EOF

    echo -e "  🎯 Created plugin advertiser configuration"
}

# Function to create a project-level plugin suggestion
create_project_plugin_config() {
    if [ -n "$FOLDER" ] && [ -d "$FOLDER" ]; then
        local idea_dir="$FOLDER/.idea"
        mkdir -p "$idea_dir"
        
        echo -e "$${BOLD}📁 Creating project-level plugin suggestions...$${RESET}"
        
        # Create externalDependencies.xml to suggest plugins
        cat > "$idea_dir/externalDependencies.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ExternalDependencies">
$(for plugin_id in "$${PLUGINS[@]}"; do
    if [ -n "$plugin_id" ]; then
        echo "    <plugin id=\"$plugin_id\" />"
    fi
done)
  </component>
</project>
EOF
        
        echo -e "  📝 Created project plugin dependencies in $${BLUE}$idea_dir/externalDependencies.xml$${RESET}"
        
        # Create workspace.xml for plugin recommendations
        cat > "$idea_dir/workspace.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="PropertiesComponent">
    <property name="plugins.to.install" value="$(IFS=','; echo "$${PLUGINS[*]}")" />
  </component>
</project>
EOF
        
        echo -e "  🔧 Created workspace plugin recommendations"
    fi
}

# Main execution
if [ $${#PLUGINS[@]} -eq 0 ]; then
    echo "No plugins specified for configuration."
    exit 0
fi

echo -e "$${BOLD}🚀 JetBrains Plugin Configuration Setup$${RESET}"
echo -e "Configuring $${#PLUGINS[@]} plugin(s) for auto-installation..."
echo -e "Selected IDEs: $${SELECTED_IDES[*]}"
echo

# Create plugin configurations for each selected IDE
for ide_code in "$${SELECTED_IDES[@]}"; do
    create_plugin_config "$ide_code"
    echo
done

# Create project-level plugin suggestions
create_project_plugin_config

echo
echo -e "$${GREEN}✨ Plugin configuration complete!$${RESET}"
echo -e "$${YELLOW}📋 When you connect via JetBrains Gateway:$${RESET}"
echo -e "   1. The IDE backend will be automatically downloaded"
echo -e "   2. Configured plugins will be suggested for installation"
echo -e "   3. You can accept the plugin installation prompts"
echo -e "   4. Plugins will be installed and activated"