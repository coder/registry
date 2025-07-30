#!/bin/bash

# Check if RustDesk is installed
if ! command -v rustdesk &> /dev/null; then
  echo "RustDesk is not installed. Installing..."

  # Download RustDesk manually
  RUSTDESK_VERSION="1.4.0"
  RUSTDESK_DEB="rustdesk-$RUSTDESK_VERSION-x86_64.deb"

  echo "Downloading RustDesk $RUSTDESK_VERSION..."
  wget "https://github.com/rustdesk/rustdesk/releases/download/$RUSTDESK_VERSION/$RUSTDESK_DEB"

  # Check if download was successful
  if [ $? -eq 0 ]; then
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y libva2 libva-drm2 libva-x11-2 libgstreamer-plugins-base1.0-0 gstreamer1.0-pipewire xfce4 xfce4-goodies xvfb x11-xserver-utils dbus-x11
    echo "Installing RustDesk..."
    sudo dpkg -i $RUSTDESK_DEB
    sudo apt-get install -f -y # To fix any dependencies
    rm $RUSTDESK_DEB # Clean up
  else
    echo "Failed to download RustDesk. Please check your network connection."
    exit 1
  fi
else
  echo "RustDesk is already installed."
fi

# Start perform other necessary actions perform other necessary actions
echo "Starting Rustdesk..."
# Start virtual display
Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99

# Wait for X to be ready
for i in {1..10}; do
    if xdpyinfo -display :99 >/dev/null 2>&1; then
        echo "X display is ready"
        break
    fi
    sleep 1
done

# Start desktop environment
xfce4-session &
# Wait for xfce session to be ready (rudimentary check)
echo "Waiting for xfce4-session to initialize..."
sleep 5  # Adjust if needed

rustdesk &
# Start RustDesk with password
generated=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 6 | head -n 1)
rustdesk --password "$generated" &

sleep 5

rid=$(rustdesk --get-id)
echo "The ID is: $rid"
echo "The password is: $generated"
