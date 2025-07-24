#!/bin/bash

# Check if RustDesk is installed
if ! command -v rustdesk &> /dev/null; then
  echo "RustDesk is not installed. Installing..."

  # Download RustDesk manually
  RUSTDESK_VERSION="1.4.0"
  RUSTDESK_DEB="rustdesk-${RUSTDESK_VERSION}-x86_64.deb"

  echo "Downloading RustDesk ${RUSTDESK_VERSION}..."
  wget "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${RUSTDESK_DEB}"

  # Check if download was successful
  if [ $? -eq 0 ]; then
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y libva2 libva-drm2 libva-x11-2 libgstreamer-plugins-base1.0-0 gstreamer1.0-pipewire
    echo "Installing RustDesk..."
    sudo dpkg -i "${RUSTDESK_DEB}"
    sudo apt-get install -f -y # To fix any dependencies
    rm "${RUSTDESK_DEB}" # Clean up
  else
    echo "Failed to download RustDesk. Please check your network connection."
    exit 1
  fi
else
  echo "RustDesk is already installed."
fi

# Start perform other necessary actions perform other necessary actions
echo "Starting Rustdesk..."
generated=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 6 | head -n 1)
rustdesk --password "$generated"
rid=$(rustdesk --get-id)
echo "The ID is: $rid"

echo "The password is: $generated"