#!/usr/bin/env bash
# Pre-install script for the kiro-crew module. Installs the system packages
# that the Kiro CLI and Kiro Crew installers need.
set -euo pipefail

sudo apt-get update -qq

# curl, unzip, openssl, and sha256sum (coreutils) are used by the installers;
# Kiro Crew verifies its signed manifest with openssl and sha256sum.
sudo apt-get install -y -qq \
  curl \
  unzip \
  gnupg \
  dirmngr \
  openssl \
  ca-certificates \
  python3-venv \
  python3-pip

# Kiro Crew creates its managed venv at ~/.kiro/crew-venv with the newest of
# python3.12, python3.11, and python3.10. Install python3.11 and its venv
# module as well so the installer has a tested interpreter.
if ! python3.11 --version > /dev/null 2>&1; then
  echo "Installing Python 3.11 from the deadsnakes PPA..."
  sudo apt-get install -y -qq software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
fi
sudo apt-get install -y -qq \
  python3.11 \
  python3.11-venv \
  python3.11-dev

echo "Kiro Crew prerequisites installed."
