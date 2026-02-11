#!/usr/bin/env bash

set -eo pipefail

error() {
  printf "💀 ERROR: %s\n" "$@"
  exit 1
}

# Function to check if Parsec is already installed
check_installed() {
  if command -v parsecd &> /dev/null; then
    echo "Parsec is already installed."
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
    echo "ERROR: No download tool available (curl, wget, or busybox required)"
    exit 1
  fi

  "$${download_tool[@]}" "$url" > "$output" || {
    echo "ERROR: Failed to download $url"
    exit 1
  }
}

# Function to install Parsec for debian-based distros
install_deb() {
  local url="https://builds.parsec.app/package/parsec-linux.deb"
  local parsecdeb="/tmp/parsec-linux.deb"

  echo "Downloading Parsec for Debian/Ubuntu..."
  download_file "$url" "$parsecdeb"

  CACHE_DIR="/var/lib/apt/lists/partial"
  # Check if the directory exists and was modified in the last 60 minutes
  if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(find "$CACHE_DIR" -mmin -60 -print -quit 2>/dev/null)" ]]; then
    echo "Stale package cache, updating..."
    sudo apt-get -o DPkg::Lock::Timeout=300 -qq update
  fi

  echo "Installing Parsec..."
  DEBIAN_FRONTEND=noninteractive sudo apt-get -o DPkg::Lock::Timeout=300 install --yes -qq --no-install-recommends --no-install-suggests "$parsecdeb"
  rm "$parsecdeb"
}

# Function to install Parsec for rpm-based distros
install_rpm() {
  local url="https://builds.parsec.app/package/parsec-linux.rpm"
  local parsecrpm="/tmp/parsec-linux.rpm"
  local package_manager

  if command -v dnf &> /dev/null; then
    package_manager=(dnf localinstall -y)
  elif command -v zypper &> /dev/null; then
    package_manager=(zypper install -y)
  elif command -v yum &> /dev/null; then
    package_manager=(yum localinstall -y)
  elif command -v rpm &> /dev/null; then
    package_manager=(rpm -i)
  else
    echo "ERROR: No supported package manager available (dnf, zypper, yum, or rpm required)"
    exit 1
  fi

  echo "Downloading Parsec for RPM-based distros..."
  download_file "$url" "$parsecrpm"

  echo "Installing Parsec..."
  sudo "$${package_manager[@]}" "$parsecrpm" || {
    echo "ERROR: Failed to install $parsecrpm"
    exit 1
  }

  rm "$parsecrpm"
}

# Detect system information
if [[ ! -f /etc/os-release ]]; then
  echo "ERROR: Cannot detect OS: /etc/os-release not found"
  exit 1
fi

source /etc/os-release

set -u

distro="$ID"
distro_version="$VERSION_ID"
arch="$(uname -m)"

echo "Detected Distribution: $distro"
echo "Detected Version: $distro_version"
echo "Detected Architecture: $arch"

# Check architecture support
case "$arch" in
  x86_64|amd64)
    echo "Architecture supported: $arch"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $arch"
    echo "Parsec only supports x86_64/amd64 on Linux"
    exit 1
    ;;
esac

# Check if Parsec is installed, and install if not
if ! check_installed; then
  # Check for NOPASSWD sudo (required)
  if ! command -v sudo &> /dev/null || ! sudo -n true 2> /dev/null; then
    echo "ERROR: sudo NOPASSWD access required!"
    exit 1
  fi

  echo "Installing Parsec..."
  case $distro in
    ubuntu | debian | kali | pop | linuxmint)
      install_deb
      ;;
    fedora | rhel | centos | rocky | almalinux | oracle)
      install_rpm
      ;;
    *)
      echo "ERROR: Unsupported distribution: $distro"
      echo "Parsec officially supports Ubuntu 18.04+ and similar Debian-based distros"
      exit 1
      ;;
  esac
else
  echo "Parsec already installed. Skipping installation."
fi

# Configure Parsec
echo "Configuring Parsec..."

# Create config directory if it doesn't exist
mkdir -p "$HOME/.parsec"

# Note: Parsec requires authentication via the web interface or CLI
# For automated setup, users need to provide their session ID or use the web login
echo "⚠️  IMPORTANT: Parsec requires authentication!"
echo "Please visit http://localhost:${PORT} to complete the setup"
echo "Or use 'parsecd' command to authenticate via CLI"

# Start Parsec daemon
echo "🚀 Starting Parsec..."

# Parsec daemon runs in the background
parsecd app_host=1 &

# Wait a moment for the daemon to start
sleep 3

# Check if Parsec is running
if pgrep -x "parsecd" > /dev/null; then
  echo "✅ Parsec started successfully!"
  echo "Access Parsec at: http://localhost:${PORT}"
else
  echo "❌ Failed to start Parsec daemon"
  exit 1
fi

# Keep the script running
wait
