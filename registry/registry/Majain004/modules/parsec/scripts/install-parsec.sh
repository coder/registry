#!/bin/bash
set -e

# Install Parsec on Linux
# This script installs Parsec for remote desktop and cloud gaming

PARSEC_URL="https://builds.parsecgaming.com/package/parsec-linux.deb"
INSTALL_PATH="$HOME/parsec"

echo "Creating installation directory..."
mkdir -p "$INSTALL_PATH"
cd "$INSTALL_PATH"

echo "Downloading Parsec installer..."
if ! wget -O parsec.deb "$PARSEC_URL"; then
    echo "Failed to download Parsec installer"
    exit 1
fi

echo "Installing Parsec..."
if ! sudo dpkg -i parsec.deb; then
    echo "Installing dependencies..."
    sudo apt-get install -f -y
fi

# Start Parsec in the background
echo "Starting Parsec..."
display_num=0
if ! pgrep Xorg; then
    echo "Starting Xvfb..."
    Xvfb :$display_num &
    export DISPLAY=:$display_num
fi

echo "Launching Parsec..."
nohup parsec > parsec.log 2>&1 &
echo "Parsec installation and startup completed successfully" 