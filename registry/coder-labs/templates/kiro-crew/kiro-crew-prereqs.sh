#!/usr/bin/env bash
# Pre-install script for the kiro-crew module. Installs the system packages
# the Kiro CLI and Kiro Crew installers need. The Kiro Crew installer
# provisions its own managed Python via uv, so no system Python is required.
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
  ca-certificates

echo "Kiro Crew prerequisites installed."
