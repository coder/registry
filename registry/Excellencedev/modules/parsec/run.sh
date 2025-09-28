#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Convert templated variables to shell variables
PARSEC_VERSION=${PARSEC_VERSION}
SERVER_ID=${SERVER_ID}
PEER_ID=${PEER_ID}

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

error() {
  printf '\033[0;31m💀 ERROR: %s\033[0m\n' "$@"
  exit 1
}

info() {
  printf '\033[0;32mℹ️  INFO: %s\033[0m\n' "$@"
}

warn() {
  printf '\033[1;33m⚠️  WARNING: %s\033[0m\n' "$@"
}

# Function to check if Parsec is already installed
check_installed() {
  if command -v parsecd &> /dev/null; then
    info "Parsec is already installed."
    return 0
  else
    return 1
  fi
}

# Function to download a file using wget, curl, or busybox as a fallback
download_file() {
  local url="$1"
  local output="$2"
  local download_tool

  if command -v curl &> /dev/null; then
    download_tool=(curl -fsSL)
  elif command -v wget &> /dev/null; then
    download_tool=(wget -q -O-)
  elif command -v busybox &> /dev/null; then
    download_tool=(busybox wget -O-)
  else
    error "No download tool available (curl, wget, or busybox required)"
  fi

  # shellcheck disable=SC2288
  "$${download_tool[@]}" "$url" > "$output" || {
    error "Failed to download $url"
  }
}

# Function to install Parsec for Ubuntu/Debian
install_deb() {
  local url="$1"
  local parsecdeb="/tmp/parsec.deb"

  download_file "$url" "$parsecdeb"

  # Update package cache if needed
  if ! dpkg -l | grep -q "parsec"; then
    info "Installing Parsec package..."
    sudo dpkg -i "$parsecdeb" || {
      warn "dpkg failed, trying to fix dependencies..."
      sudo apt-get update
      sudo apt-get install -f -y
      sudo dpkg -i "$parsecdeb"
    }
  fi

  rm "$parsecdeb"
}

# Function to install Parsec for CentOS/RHEL/Fedora
install_rpm() {
  local url="$1"
  local parsecrpm="/tmp/parsec.rpm"

  download_file "$url" "$parsecrpm"

  if command -v dnf &> /dev/null; then
    sudo dnf install -y "$parsecrpm"
  elif command -v yum &> /dev/null; then
    sudo yum localinstall -y "$parsecrpm"
  else
    error "No supported package manager available (dnf or yum required)"
  fi

  rm "$parsecrpm"
}

# Detect system information
if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS: /etc/os-release not found"
fi

# shellcheck disable=SC1091
source /etc/os-release
distro="$ID"
distro_version="$VERSION_ID"
arch="$(uname -m)"

# Map architecture
case "$arch" in
  x86_64)
    arch="amd64"
    ;;
  aarch64)
    arch="arm64"
    ;;
  *)
    error "Unsupported architecture: $arch"
    ;;
esac

info "Detected Distribution: $distro"
info "Detected Version: $distro_version"
info "Detected Architecture: $arch"

# Check if Parsec is installed, and install if not
if ! check_installed; then
  # Check for sudo access
  if ! command -v sudo &> /dev/null || ! sudo -n true 2> /dev/null; then
    error "sudo access required for Parsec installation!"
  fi

  printf '\033[0;1m🚀 Installing Parsec...\n\n\033[0m'

  # Determine download URL based on version
  if [[ "$PARSEC_VERSION" == "latest" ]]; then
    base_url="https://builds.parsec.app/package"
  else
    base_url="https://builds.parsec.app/package/v${PARSEC_VERSION}"
  fi

  case $distro in
    ubuntu | debian | kali | linuxmint | pop)
      bin_name="parsec-linux.deb"
      install_deb "$base_url/$bin_name"
      ;;
    centos | rhel | fedora | ol)
      bin_name="parsec-linux.rpm"
      install_rpm "$base_url/$bin_name"
      ;;
    *)
      error "Unsupported distribution: $distro. Parsec supports Ubuntu/Debian and CentOS/RHEL/Fedora."
      ;;
  esac
else
  info "Parsec already installed. Skipping installation."
fi

printf '\033[0;1m⚙️  Configuring Parsec...\n\n\033[0m'

# Create Parsec configuration directory
mkdir -p "$HOME/.parsec"

# Configure Parsec for headless operation
cat > "$HOME/.parsec/config.txt" << EOF
app_run_level = 1
server_bind_port = 8000
server_bind_ip = 127.0.0.1
encoder_bitrate = 100
encoder_min_bitrate = 10
encoder_max_bitrate = 100
client_port = 0
host_port = 0
EOF

# Set custom IDs if provided
if [[ -n "$SERVER_ID" ]]; then
  echo "server_id = $SERVER_ID" >> "$HOME/.parsec/config.txt"
fi

if [[ -n "$PEER_ID" ]]; then
  echo "peer_id = $PEER_ID" >> "$HOME/.parsec/config.txt"
fi

# Create systemd service for Parsec (if systemd is available)
if command -v systemctl &> /dev/null; then
  info "Setting up Parsec systemd service..."

  sudo tee /etc/systemd/system/parsec.service > /dev/null << EOF
[Unit]
Description=Parsec Cloud Gaming
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/parsecd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable parsec
  sudo systemctl start parsec

  info "Parsec service started and enabled."
else
  warn "systemd not available, starting Parsec manually..."

  # Start Parsec in background
  nohup /usr/bin/parsecd > /tmp/parsec.log 2>&1 &
  PARSEC_PID=$!

  # Save PID for potential cleanup
  echo $PARSEC_PID > /tmp/parsec.pid

  info "Parsec started with PID: $PARSEC_PID"
fi

# Wait a moment for Parsec to start
sleep 3

# Check if Parsec is running
if pgrep -f parsecd > /dev/null; then
  printf '\033[0;32m✅ Parsec installation and configuration complete!\033[0m\n\n'
  info "Parsec web interface should be available at http://localhost:8000"
  info "You can now connect to this workspace using the Parsec client."
else
  error "Parsec failed to start. Check logs for details."
fi
