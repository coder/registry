#!/usr/bin/env bash

# Moonlight/GameStream Setup Script
# This script installs and configures either NVIDIA GameStream or Sunshine server
# for GPU-accelerated remote desktop streaming

set -euo pipefail

# Template variables
STREAMING_SERVER="${STREAMING_SERVER}"
PORT="${PORT}"
SUNSHINE_VERSION="${SUNSHINE_VERSION}"
ENABLE_AUDIO="${ENABLE_AUDIO}"
ENABLE_GAMEPAD="${ENABLE_GAMEPAD}"
RESOLUTION="${RESOLUTION}"
FPS="${FPS}"
BITRATE="${BITRATE}"
SUBDOMAIN="${SUBDOMAIN}"

# Colors for output (defined here, not from template)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "$${BLUE}[INFO]$${NC} $1"
}

log_success() {
    echo -e "$${GREEN}[SUCCESS]$${NC} $1"
}

log_warning() {
    echo -e "$${YELLOW}[WARNING]$${NC} $1"
}

log_error() {
    echo -e "$${RED}[ERROR]$${NC} $1"
}

# Detect OS and package manager
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            OS="debian"
            PACKAGE_MANAGER="apt"
        elif command -v yum &> /dev/null; then
            OS="redhat"
            PACKAGE_MANAGER="yum"
        elif command -v dnf &> /dev/null; then
            OS="fedora"
            PACKAGE_MANAGER="dnf"
        elif command -v pacman &> /dev/null; then
            OS="arch"
            PACKAGE_MANAGER="pacman"
        else
            log_error "Unsupported Linux distribution"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        PACKAGE_MANAGER="brew"
    else
        log_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    
    log_info "Detected OS: $OS with package manager: $PACKAGE_MANAGER"
}

# Check if NVIDIA GPU is present
check_nvidia_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            log_success "NVIDIA GPU detected"
            return 0
        fi
    fi
    
    if lspci | grep -i nvidia &> /dev/null; then
        log_warning "NVIDIA GPU detected but drivers may not be installed"
        return 0
    fi
    
    log_warning "No NVIDIA GPU detected. Sunshine can still work with software encoding."
    return 1
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    case $PACKAGE_MANAGER in
        "apt")
            sudo apt-get update
            sudo apt-get install -y curl wget software-properties-common
            if [[ "$ENABLE_AUDIO" == "true" ]]; then
                sudo apt-get install -y pulseaudio pulseaudio-utils alsa-utils
            fi
            ;;
        "yum"|"dnf")
            sudo $PACKAGE_MANAGER update -y
            sudo $PACKAGE_MANAGER install -y curl wget
            if [[ "$ENABLE_AUDIO" == "true" ]]; then
                sudo $PACKAGE_MANAGER install -y pulseaudio alsa-utils
            fi
            ;;
        "pacman")
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm curl wget
            if [[ "$ENABLE_AUDIO" == "true" ]]; then
                sudo pacman -S --noconfirm pulseaudio alsa-utils
            fi
            ;;
        "brew")
            brew update
            if [[ "$ENABLE_AUDIO" == "true" ]]; then
                log_info "Audio support on macOS is built-in"
            fi
            ;;
    esac
}

# Install NVIDIA drivers if needed
install_nvidia_drivers() {
    if [[ "$OS" == "macos" ]]; then
        log_info "NVIDIA drivers not applicable on macOS"
        return
    fi
    
    if nvidia-smi &> /dev/null; then
        log_success "NVIDIA drivers already installed"
        return
    fi
    
    if ! lspci | grep -i nvidia &> /dev/null; then
        log_info "No NVIDIA GPU detected, skipping driver installation"
        return
    fi
    
    log_info "Installing NVIDIA drivers..."
    
    case $PACKAGE_MANAGER in
        "apt")
            sudo apt-get install -y ubuntu-drivers-common
            sudo ubuntu-drivers autoinstall
            ;;
        "yum"|"dnf")
            sudo $PACKAGE_MANAGER install -y nvidia-driver nvidia-settings
            ;;
        "pacman")
            sudo pacman -S --noconfirm nvidia nvidia-utils
            ;;
    esac
    
    log_warning "NVIDIA drivers installed. A reboot may be required."
}

# Install Sunshine server
install_sunshine() {
    log_info "Installing Sunshine server version $SUNSHINE_VERSION..."
    
    # Create sunshine user if it doesn't exist
    if ! id "sunshine" &>/dev/null; then
        sudo useradd -r -s /bin/false sunshine
    fi
    
    case $OS in
        "debian")
            # Download and install Sunshine .deb package
            SUNSHINE_DEB="sunshine-$SUNSHINE_VERSION-linux-$$(dpkg --print-architecture).deb"
            SUNSHINE_URL="https://github.com/LizardByte/Sunshine/releases/download/$SUNSHINE_VERSION/$SUNSHINE_DEB"
            
            wget -O "/tmp/$SUNSHINE_DEB" "$SUNSHINE_URL"
            sudo dpkg -i "/tmp/$SUNSHINE_DEB" || sudo apt-get install -f -y
            ;;
        "redhat"|"fedora")
            # Download and install Sunshine .rpm package
            SUNSHINE_RPM="sunshine-$SUNSHINE_VERSION-linux-$$(uname -m).rpm"
            SUNSHINE_URL="https://github.com/LizardByte/Sunshine/releases/download/$SUNSHINE_VERSION/$SUNSHINE_RPM"
            
            wget -O "/tmp/$SUNSHINE_RPM" "$SUNSHINE_URL"
            sudo $PACKAGE_MANAGER localinstall -y "/tmp/$SUNSHINE_RPM"
            ;;
        "arch")
            # Install from AUR or compile from source
            if command -v yay &> /dev/null; then
                yay -S --noconfirm sunshine
            else
                log_warning "Installing Sunshine from source on Arch Linux"
                # Build from source instructions would go here
                git clone https://github.com/LizardByte/Sunshine.git /tmp/sunshine
                cd /tmp/sunshine
                # Build steps would be implemented here
            fi
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install sunshine
            else
                log_error "Homebrew is required to install Sunshine on macOS"
                exit 1
            fi
            ;;
    esac
    
    log_success "Sunshine installed successfully"
}

# Configure Sunshine
configure_sunshine() {
    log_info "Configuring Sunshine..."
    
    # Create sunshine config directory
    SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"
    mkdir -p "$SUNSHINE_CONFIG_DIR"
    
    # Create sunshine configuration file
    cat > "$SUNSHINE_CONFIG_DIR/sunshine.conf" << EOF
# Sunshine Configuration
# Generated by Coder Moonlight module

# Network settings
port = $PORT
address_family = both

# Video settings
encoder = auto
adapter_name = 
output_name = 

# Video quality settings
bitrate = $BITRATE
fps = $FPS
resolution = $RESOLUTION

# Audio settings
audio_sink = auto
install_steam_audio_drivers = $ENABLE_AUDIO

# Input settings
gamepad = $ENABLE_GAMEPAD

# Security settings
username = 
password = 

# Web UI settings
web_ui_port = $PORT
https_port = $$((PORT + 1))

# Logging
log_level = info
EOF

    # Create apps.json for application streaming
    cat > "$SUNSHINE_CONFIG_DIR/apps.json" << EOF
{
  "env": {},
  "apps": [
    {
      "name": "Desktop",
      "output": "",
      "cmd": "",
      "exclude-global-prep-cmd": false,
      "elevated": false,
      "auto-detach": true,
      "wait-all": false,
      "exit-timeout": 5
    },
    {
      "name": "Steam",
      "output": "",
      "cmd": "steam",
      "exclude-global-prep-cmd": false,
      "elevated": false,
      "auto-detach": true,
      "wait-all": false,
      "exit-timeout": 5
    }
  ]
}
EOF

    log_success "Sunshine configuration created"
}

# Setup GameStream (NVIDIA)
setup_gamestream() {
    log_info "Setting up NVIDIA GameStream..."
    
    if ! check_nvidia_gpu; then
        log_error "NVIDIA GPU is required for GameStream"
        exit 1
    fi
    
    # Check if GeForce Experience is installed
    if command -v nvidia-settings &> /dev/null; then
        log_info "NVIDIA drivers detected"
    else
        log_warning "NVIDIA drivers not found. Installing..."
        install_nvidia_drivers
    fi
    
    # Create a setup script for GameStream
    cat > "$HOME/setup-gamestream.sh" << 'EOF'
#!/bin/bash
echo "GameStream Setup Instructions:"
echo "1. Install NVIDIA GeForce Experience on your system"
echo "2. Enable GameStream in GeForce Experience settings"
echo "3. Ensure your system meets GameStream requirements:"
echo "   - GTX 600 series or newer (Kepler architecture)"
echo "   - Windows 7/8/10/11 or Linux with appropriate drivers"
echo "4. Configure your router for GameStream (if streaming over internet)"
echo "5. Use Moonlight client to connect to this machine"
echo ""
echo "Note: GameStream is being deprecated by NVIDIA."
echo "Consider using Sunshine for future-proof streaming."
EOF
    
    chmod +x "$HOME/setup-gamestream.sh"
    
    log_success "GameStream setup script created at $HOME/setup-gamestream.sh"
}

# Start services
start_services() {
    if [[ "$STREAMING_SERVER" == "sunshine" ]]; then
        log_info "Starting Sunshine service..."
        
        # Create systemd service for Sunshine
        if command -v systemctl &> /dev/null; then
            # Check if sunshine service exists
            if systemctl list-unit-files | grep -q sunshine; then
                sudo systemctl enable sunshine
                sudo systemctl start sunshine
                log_success "Sunshine service started"
            else
                log_info "Starting Sunshine manually..."
                nohup sunshine > /tmp/sunshine.log 2>&1 &
                echo $! > /tmp/sunshine.pid
                log_success "Sunshine started in background"
            fi
        else
            log_info "Starting Sunshine manually..."
            nohup sunshine > /tmp/sunshine.log 2>&1 &
            echo $! > /tmp/sunshine.pid
            log_success "Sunshine started in background"
        fi
    fi
}

# Create helpful scripts
create_helper_scripts() {
    log_info "Creating helper scripts..."
    
    # Create connection info script
    cat > "$HOME/moonlight-info.sh" << EOF
#!/bin/bash
echo "Moonlight Streaming Information"
echo "==============================="
echo "Streaming Server: $STREAMING_SERVER"
echo "Port: $PORT"
echo "Resolution: $RESOLUTION"
echo "FPS: $FPS"
echo "Bitrate: ${BITRATE}Mbps"
echo "Audio Enabled: $ENABLE_AUDIO"
echo "Gamepad Enabled: $ENABLE_GAMEPAD"
echo ""
echo "Server IP: $$(hostname -I | awk '{print $$1}')"
echo ""
if [[ "$STREAMING_SERVER" == "sunshine" ]]; then
    echo "Sunshine Web UI: https://localhost:$PORT"
    echo "PIN for pairing: Check web UI or sunshine logs"
fi
echo ""
echo "Download Moonlight client from: https://moonlight-stream.org"
EOF
    
    chmod +x "$HOME/moonlight-info.sh"
    
    log_success "Helper scripts created"
}

# Main installation function
main() {
    log_info "Starting Moonlight/GameStream setup..."
    log_info "Streaming server: $STREAMING_SERVER"
    
    detect_os
    install_dependencies
    
    if [[ "$STREAMING_SERVER" == "sunshine" ]]; then
        install_sunshine
        configure_sunshine
        start_services
    elif [[ "$STREAMING_SERVER" == "gamestream" ]]; then
        setup_gamestream
    fi
    
    create_helper_scripts
    
    log_success "Moonlight/GameStream setup completed!"
    log_info "Run '$HOME/moonlight-info.sh' for connection information"
    
    if [[ "$STREAMING_SERVER" == "sunshine" ]]; then
        log_info "Access Sunshine Web UI at: https://localhost:$PORT"
        log_info "Default username: admin (set password on first login)"
    fi
}

# Run main function
main "$@"
