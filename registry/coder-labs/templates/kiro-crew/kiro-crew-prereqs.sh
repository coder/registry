#!/usr/bin/env bash
# Pre-install script for the kiro-crew module. Installs the system packages
# the Kiro CLI and Kiro Crew installers need. The Kiro Crew installer
# provisions its own managed Python via uv, so no system Python is required.
set -euo pipefail

sudo apt-get update -qq

# curl, unzip, openssl, and sha256sum (coreutils) are what the Kiro CLI and
# Kiro Crew installers need: curl to download, unzip to extract the Kiro CLI
# archive, and openssl plus sha256sum to verify the Kiro Crew signed manifest.
# The default codercom/enterprise-base image already ships these, so this is a
# safety net for leaner images. The Kiro Crew installer provisions its own
# Python via uv, so no Python packages (and no gnupg/PPA tooling) are needed.
sudo apt-get install -y -qq \
  curl \
  unzip \
  openssl \
  ca-certificates

echo "Kiro Crew prerequisites installed."
