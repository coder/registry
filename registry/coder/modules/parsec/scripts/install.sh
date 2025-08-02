#!/bin/bash
set -euo pipefail

BOLD='\033[0;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse configuration
PARSEC_CONFIG=$(echo "$PARSEC_CONFIG" | base64 -d)

printf "${BLUE}Starting Parsec installation...${NC}\n"

# Check if we're running on a supported system
if [ "$(uname)" != "Linux" ]; then
    printf "${RED}Error: This module only supports Linux systems${NC}\n"
    exit 1
fi

# Install dependencies
printf "${BLUE}Installing dependencies...${NC}\n"
if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian
    sudo apt-get update
    sudo apt-get install -y \
        libegl1-mesa \
        libgl1-mesa-glx \
        libvdpau1 \
        x11-xserver-utils \
        pulseaudio \
        curl \
        jq
elif command -v dnf &> /dev/null; then
    # Fedora/RHEL
    sudo dnf install -y \
        mesa-libEGL \
        mesa-libGL \
        libvdpau \
        xorg-x11-server-utils \
        pulseaudio \
        curl \
        jq
else
    printf "${RED}Error: Unsupported Linux distribution${NC}\n"
    exit 1
fi

# Download and install Parsec
printf "${BLUE}Downloading Parsec...${NC}\n"
if [ "$PARSEC_VERSION" = "latest" ]; then
    DOWNLOAD_URL="https://builds.parsec.app/package/parsec-linux.deb"
else
    DOWNLOAD_URL="https://builds.parsec.app/package/parsec-linux-${PARSEC_VERSION}.deb"
fi

wget -O /tmp/parsec.deb "$DOWNLOAD_URL"
sudo dpkg -i /tmp/parsec.deb || sudo apt-get -f install -y
rm /tmp/parsec.deb

# Create Parsec configuration directory
PARSEC_CONFIG_DIR="$HOME/.config/parsec"
mkdir -p "$PARSEC_CONFIG_DIR"

# Configure Parsec
printf "${BLUE}Configuring Parsec...${NC}\n"
cat > "$PARSEC_CONFIG_DIR/config.txt" << EOL
# Parsec Configuration
app_host = 1
app_run_level = 3
encoder_bitrate = $(jq -r '.encoder_bitrate // 50' <<< "$PARSEC_CONFIG")
encoder_fps = $(jq -r '.encoder_fps // 60' <<< "$PARSEC_CONFIG")
encoder_min_bitrate = 10
bandwidth_limit = $(jq -r '.bandwidth_limit // 100' <<< "$PARSEC_CONFIG")
encoder_h265 = $(jq -r '.encoder_h265 // true' <<< "$PARSEC_CONFIG")
client_keyboard_layout = $(jq -r '.client_keyboard_layout // "en-us"' <<< "$PARSEC_CONFIG")
host_virtual_monitors = 1
EOL

# Configure host key
if [ -n "$PARSEC_HOST_KEY" ]; then
    echo "host_key = $PARSEC_HOST_KEY" >> "$PARSEC_CONFIG_DIR/config.txt"
fi

# Configure GPU acceleration if enabled
if [ "$ENABLE_GPU" = "true" ]; then
    printf "${BLUE}Configuring GPU acceleration...${NC}\n"
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        echo "encoder_device = 0" >> "$PARSEC_CONFIG_DIR/config.txt"
    else
        printf "${RED}Warning: GPU acceleration enabled but no NVIDIA GPU found${NC}\n"
    fi
fi

# Set up autostart if enabled
if [ "$AUTO_START" = "true" ]; then
    printf "${BLUE}Configuring autostart...${NC}\n"
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/parsec.desktop" << EOL
[Desktop Entry]
Type=Application
Name=Parsec
Exec=parsecd
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOL
fi

# Start Parsec daemon
if [ "$AUTO_START" = "true" ]; then
    printf "${BLUE}Starting Parsec daemon...${NC}\n"
    parsecd &
fi

printf "${GREEN}Parsec installation and configuration complete!${NC}\n"
printf "You can now connect to this workspace using the Parsec client.\n"
