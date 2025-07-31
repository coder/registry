#!/bin/bash
set -e

# Moonlight Installation Script for Linux
# Installs and configures Moonlight streaming with automatic GPU detection

STREAMING_METHOD=${STREAMING_METHOD:-"auto"}
PORT=${PORT:-47984}
QUALITY=${QUALITY:-"high"}

echo "Starting Moonlight installation..."

# Function to detect GPU and determine streaming method
detect_gpu() {
    echo "Detecting GPU hardware..."
    
    if command -v lspci &> /dev/null; then
        nvidia_gpus=$(lspci | grep -i nvidia)
        
        if [ -n "$nvidia_gpus" ]; then
            echo "NVIDIA GPU detected:"
            echo "$nvidia_gpus"
            
            if command -v nvidia-smi &> /dev/null; then
                echo "NVIDIA drivers found - using GameStream"
                echo "gamestream"
            else
                echo "NVIDIA drivers not found - using Sunshine"
                echo "sunshine"
            fi
        else
            echo "No NVIDIA GPU detected - using Sunshine"
            echo "sunshine"
        fi
    else
        echo "lspci not available - using Sunshine"
        echo "sunshine"
    fi
}

# Determine streaming method
if [ "$STREAMING_METHOD" = "auto" ]; then
    STREAMING_METHOD=$(detect_gpu)
fi

echo "Using streaming method: $STREAMING_METHOD"

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install dependencies
echo "Installing dependencies..."
sudo apt-get install -y wget curl unzip

# Install Moonlight client
echo "Installing Moonlight client..."
if command -v snap &> /dev/null; then
    sudo snap install moonlight
    echo "Moonlight installed via snap"
else
    # Download and install Moonlight manually
    moonlight_url="https://github.com/moonlight-stream/moonlight-qt/releases/latest/download/Moonlight-qt-x86_64.AppImage"
    moonlight_appimage="$HOME/moonlight.AppImage"
    
    wget -O "$moonlight_appimage" "$moonlight_url"
    chmod +x "$moonlight_appimage"
    echo "Moonlight AppImage downloaded"
fi

# Configure streaming server based on method
if [ "$STREAMING_METHOD" = "gamestream" ]; then
    echo "Configuring NVIDIA GameStream..."
    
    # Check if nvidia-smi is available
    if command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA drivers found - GameStream should be available"
        echo "Please ensure GameStream is enabled in GeForce Experience settings"
    else
        echo "NVIDIA drivers not found - please install them for GameStream"
    fi
else
    echo "Installing Sunshine server..."
    
    # Download and install Sunshine
    sunshine_url="https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-linux-x64.tar.gz"
    sunshine_tar="$HOME/sunshine.tar.gz"
    sunshine_dir="/opt/sunshine"
    
    wget -O "$sunshine_tar" "$sunshine_url"
    sudo mkdir -p "$sunshine_dir"
    sudo tar -xzf "$sunshine_tar" -C "$sunshine_dir" --strip-components=1
    sudo chmod +x "$sunshine_dir/sunshine"
    
    # Create systemd service for Sunshine
    cat << EOF | sudo tee /etc/systemd/system/sunshine.service
[Unit]
Description=Sunshine GameStream Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=$sunshine_dir/sunshine
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure Sunshine
    cat << EOF | sudo tee "$sunshine_dir/sunshine.conf"
# Sunshine Configuration
port = $PORT
quality = $QUALITY
fps = 60
encoder = nvenc
EOF
    
    # Enable and start Sunshine service
    sudo systemctl enable sunshine.service
    sudo systemctl start sunshine.service
    
    echo "Sunshine installed and configured successfully"
fi

# Configure firewall rules
echo "Configuring firewall rules..."
if command -v ufw &> /dev/null; then
    sudo ufw allow $PORT/tcp
    echo "Firewall rule added via ufw"
elif command -v iptables &> /dev/null; then
    sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    echo "Firewall rule added via iptables"
else
    echo "No firewall manager detected - please configure manually"
fi

echo "Moonlight installation completed successfully"
echo "Streaming method: $STREAMING_METHOD"
echo "Port: $PORT"
echo "Quality: $QUALITY" 