#!/bin/bash
set -e

PARSEC_URL="https://builds.parsecgaming.com/package/parsec-linux.deb"
INSTALL_PATH="$HOME/parsec"

mkdir -p "$INSTALL_PATH"
cd "$INSTALL_PATH"

wget -O parsec.deb "$PARSEC_URL"
sudo dpkg -i parsec.deb || sudo apt-get install -f -y

# Start Parsec in the background
display_num=0
if ! pgrep Xorg; then
  Xvfb :$display_num &
  export DISPLAY=:$display_num
fi
nohup parsec &