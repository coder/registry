#!/bin/bash

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
echo "folder: $ARG_FOLDER"
echo "install: $ARG_INSTALL"
echo "enable_mcp: $ARG_ENABLE_MCP"
echo "mcp_config_path: $ARG_MCP_CONFIG_PATH"
echo "enable_force_mode: $ARG_ENABLE_FORCE_MODE"
echo "default_model: $ARG_DEFAULT_MODEL"
echo "enable_rules: $ARG_ENABLE_RULES"
echo "--------------------------------"

set +o nounset

if [ "${ARG_INSTALL}" = "true" ]; then
  echo "Installing Cursor CLI..."

  # Install Cursor CLI using the official installer
  curl https://cursor.com/install -fsS | bash

  # Add cursor-agent to PATH if not already there
  if ! command_exists cursor-agent; then
    echo 'export PATH="$HOME/.cursor/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.cursor/bin:$PATH"' >> "$HOME/.zshrc" 2> /dev/null || true
    export PATH="$HOME/.cursor/bin:$PATH"
  fi

  echo "Cursor CLI installed"
  
  # Configure MCP if enabled
  if [ "${ARG_ENABLE_MCP}" = "true" ]; then
    echo "Configuring MCP (Model Context Protocol)..."
    
    # Create MCP config directory if it doesn't exist
    mkdir -p "$HOME/.cursor"
    
    # If custom MCP config path is provided, copy it
    if [ -n "${ARG_MCP_CONFIG_PATH}" ] && [ -f "${ARG_MCP_CONFIG_PATH}" ]; then
      cp "${ARG_MCP_CONFIG_PATH}" "$HOME/.cursor/mcp.json"
      echo "MCP configuration copied from ${ARG_MCP_CONFIG_PATH}"
    else
      # Create a basic MCP config if none exists
      if [ ! -f "$HOME/.cursor/mcp.json" ]; then
        cat > "$HOME/.cursor/mcp.json" << 'EOF'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["@modelcontextprotocol/server-filesystem", "/tmp"]
    }
  }
}
EOF
        echo "Basic MCP configuration created"
      fi
    fi
  fi
  
  # Configure rules system if enabled
  if [ "${ARG_ENABLE_RULES}" = "true" ]; then
    echo "Setting up Cursor rules system..."
    mkdir -p "$HOME/.cursor/rules"
    
    # Create a basic rules file if none exists
    if [ ! -f "$HOME/.cursor/rules/general.md" ]; then
      cat > "$HOME/.cursor/rules/general.md" << 'EOF'
# General Coding Rules

## Code Style
- Use consistent indentation (2 spaces for JS/TS, 4 for Python)
- Add meaningful comments for complex logic
- Follow language-specific naming conventions

## Best Practices
- Write tests for new functionality
- Handle errors gracefully
- Use descriptive variable and function names
EOF
      echo "Basic rules configuration created"
    fi
  fi
else
  echo "Skipping Cursor CLI installation"
fi

# Verify installation
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -f "$HOME/.cursor/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.cursor/bin/cursor-agent"
else
  echo "Warning: Cursor CLI is not installed or not found in PATH. Please enable install_cursor_cli or install it manually."
  echo "You can install it manually with: curl https://cursor.com/install -fsS | bash"
fi

echo "Cursor CLI setup complete"
