#!/usr/bin/env bash

NVM_VERSION='${NVM_VERSION}'
NODE_VERSIONS='${NODE_VERSIONS}'
INSTALL_PREFIX='${INSTALL_PREFIX}'
DEFAULT='${DEFAULT}'
BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'

printf "$${BOLD}Installing nvm!$${RESET}\n"

export NVM_DIR="$HOME/$${INSTALL_PREFIX}/nvm"
mkdir -p "$NVM_DIR"

script="$(curl -sS -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$${NVM_VERSION}/install.sh" 2>&1)"
if [ $? -ne 0 ]; then
  echo "Failed to download nvm installation script: $script"
  exit 1
fi

output="$(bash <<< "$script" 2>&1)"
if [ $? -ne 0 ]; then
  echo "Failed to install nvm: $output"
  exit 1
fi

printf "🥳 nvm has been installed\n\n"

# Set up nvm for the rest of the script.
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Install each node version...
IFS=',' read -r -a VERSIONLIST <<< "$${NODE_VERSIONS}"
for version in "$${VERSIONLIST[@]}"; do
  if [ -z "$version" ]; then
    continue
  fi
  printf "🛠️ Installing node version $${CODE}$version$${RESET}...\n"
  output=$(nvm install "$version" 2>&1)
  if [ $? -ne 0 ]; then
    echo "Failed to install version: $version: $output"
    exit 1
  fi
done

# Set default if provided
if [ -n "$${DEFAULT}" ]; then
  printf "🛠️ Setting default node version $${CODE}$DEFAULT$${RESET}...\n"
  output=$(nvm alias default $DEFAULT 2>&1)
fi
