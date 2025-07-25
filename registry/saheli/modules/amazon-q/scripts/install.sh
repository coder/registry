#!/bin/bash

# Enhanced logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HOME/.amazon-q-module/logs/install.log"
}

# Error handling
set -e
trap 'log "ERROR: Installation failed on line $LINENO"' ERR

# Create log directory
mkdir -p "$HOME/.amazon-q-module/logs"

log "INFO: Starting Amazon Q installation..."

# Get environment variables from Terraform
INSTALL_AMAZON_Q="${ARG_INSTALL:-true}"
AMAZON_Q_VERSION="${ARG_AMAZON_Q_VERSION:-latest}"
USE_AIDER="${ARG_USE_AIDER:-false}"
AIDER_VERSION="${ARG_AIDER_VERSION:-latest}"
AMAZON_Q_CONFIG="${ARG_AMAZON_Q_CONFIG:-}"
AWS_ACCESS_KEY_ID="${ARG_AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${ARG_AWS_SECRET_ACCESS_KEY:-}"
AWS_REGION="${ARG_AWS_REGION:-us-east-1}"
AWS_PROFILE="${ARG_AWS_PROFILE:-default}"

# Check if Amazon Q is already installed
if command -v q >/dev/null 2>&1; then
    log "INFO: Amazon Q is already installed"
    q --version | tee -a "$HOME/.amazon-q-module/logs/install.log"
    exit 0
fi

# Install dependencies
log "INFO: Installing dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y curl unzip
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y curl unzip
elif command -v brew >/dev/null 2>&1; then
    brew install curl unzip
else
    log "ERROR: Could not find package manager"
    exit 1
fi

# Download and install Amazon Q
log "INFO: Downloading Amazon Q..."
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    "x86_64")
        Q_URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip"
        ;;
    "aarch64"|"arm64")
        Q_URL="https://desktop-release.codewhisperer.us-east-1.amazonaws.com/latest/q-aarch64-linux.zip"
        ;;
    *)
        log "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

log "INFO: Downloading from $Q_URL"
curl -L "$Q_URL" -o q.zip

log "INFO: Extracting Amazon Q..."
unzip q.zip

log "INFO: Installing Amazon Q..."
./q/install.sh --force

# Add to PATH
log "INFO: Configuring PATH..."
if ! grep -q "q/bin" "$HOME/.bashrc"; then
    echo 'export PATH="$PATH:$HOME/q/bin"' >> "$HOME/.bashrc"
fi

export PATH="$PATH:$HOME/q/bin"

# Verify installation
log "INFO: Verifying Amazon Q installation..."
if command -v q >/dev/null 2>&1; then
    log "SUCCESS: Amazon Q installed successfully"
    q --version | tee -a "$HOME/.amazon-q-module/logs/install.log"
else
    log "ERROR: Amazon Q installation failed"
    exit 1
fi

# Clean up
cd "$HOME"
rm -rf "$TMP_DIR"

# Configure AWS credentials (following Goose pattern)
log "INFO: Configuring AWS credentials..."
mkdir -p "$HOME/.aws"

# Create AWS config file
cat > "$HOME/.aws/config" << EOF
[default]
region = ${AWS_REGION:-us-east-1}
output = json
EOF

# Create AWS credentials file if credentials are provided
if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]; then
    cat > "$HOME/.aws/credentials" << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    log "INFO: AWS credentials configured"
else
    log "INFO: No AWS credentials provided, using environment or IAM role"
fi

# Create Amazon Q config (similar to Goose)
log "INFO: Creating Amazon Q configuration..."
mkdir -p "$HOME/.config/amazonq"
cat > "$HOME/.config/amazonq/config.yaml" << EOF
provider: aws
region: ${AWS_REGION:-us-east-1}
profile: ${AWS_PROFILE:-default}
EOF

# Install Aider if requested
if [ "$USE_AIDER" = "true" ]; then
    log "INFO: Installing Aider..."
    if ! command -v pip3 >/dev/null 2>&1; then
        log "INFO: Installing Python 3 and pip..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y python3 python3-pip
        fi
    fi
    
    # Install Aider
    if [ "$AIDER_VERSION" = "latest" ]; then
        pip3 install --user aider-chat
    else
        pip3 install --user "aider-chat==$AIDER_VERSION"
    fi
    
    # Add to PATH
    if ! grep -q ".local/bin" "$HOME/.bashrc"; then
        echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$HOME/.bashrc"
    fi
    export PATH="$PATH:$HOME/.local/bin"
    
    # Verify Aider installation
    if command -v aider >/dev/null 2>&1; then
        log "SUCCESS: Aider installed successfully"
        aider --version | tee -a "$HOME/.amazon-q-module/logs/install.log"
    else
        log "ERROR: Aider installation failed"
        exit 1
    fi
fi

# Create MCP configuration directory
log "INFO: Creating MCP configuration..."
mkdir -p "$HOME/.amazon-q-module/mcp"
mkdir -p "$HOME/.config/coder/mcp"

# Write MCP configuration if provided
if [ ! -z "$AMAZON_Q_CONFIG" ]; then
    echo "$AMAZON_Q_CONFIG" > "$HOME/.amazon-q-module/mcp/config.yaml"
    log "INFO: MCP configuration written to $HOME/.amazon-q-module/mcp/config.yaml"
    
    # Also write to Coder MCP config location for Amazon Q
    if [ "$USE_AIDER" = "true" ]; then
        echo "$AMAZON_Q_CONFIG" > "$HOME/.config/coder/mcp/aider.yaml"
        log "INFO: MCP configuration written for Aider"
    else
        echo "$AMAZON_Q_CONFIG" > "$HOME/.config/coder/mcp/amazon-q.yaml"
        log "INFO: MCP configuration written for Amazon Q"
    fi
fi

log "INFO: Installation completed successfully"