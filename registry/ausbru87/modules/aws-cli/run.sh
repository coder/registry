#!/usr/bin/env sh

set -e

LOG_PATH=${LOG_PATH}
VERSION=${VERSION}
DOWNLOAD_URL=${DOWNLOAD_URL}

BOLD='\\033[0;1m'
RESET='\\033[0m'

printf "${BOLD}Installing AWS CLI...\\n${RESET}"

# Check if AWS CLI is already installed
if command -v aws > /dev/null 2>&1; then
  INSTALLED_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
  if [ -n "$VERSION" ] && [ "$INSTALLED_VERSION" != "$VERSION" ]; then
    printf "❌ AWS CLI $INSTALLED_VERSION is installed, but version $VERSION was requested.\\n"
    printf "Note: AWS CLI installer does not support version-specific installation.\\n"
    exit 1
  else
    printf "AWS CLI is already installed ($INSTALLED_VERSION). Skipping installation.\\n"
    exit 0
  fi
fi

# Determine OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  aarch64 | arm64) ARCH="aarch64" ;;
  *)
    printf "Unsupported architecture: $ARCH\\n" >> "${LOG_PATH}" 2>&1
    exit 1
    ;;
esac

# Install AWS CLI
if [ "$OS" = "linux" ]; then
  # Use custom download URL if provided, otherwise use default AWS URL
  if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip"
  fi

  printf "Downloading AWS CLI from $DOWNLOAD_URL...\\n"
  curl -fsSL "$DOWNLOAD_URL" -o /tmp/awscliv2.zip >> "${LOG_PATH}" 2>&1 || exit 1

  unzip -q /tmp/awscliv2.zip -d /tmp >> "${LOG_PATH}" 2>&1 || exit 1
  sudo /tmp/aws/install >> "${LOG_PATH}" 2>&1 || exit 1

  rm -rf /tmp/awscliv2.zip /tmp/aws

elif [ "$OS" = "darwin" ]; then
  # Use custom download URL if provided, otherwise use architecture-specific AWS URL
  if [ -z "$DOWNLOAD_URL" ]; then
    case "$ARCH" in
      x86_64)
        DOWNLOAD_URL="https://awscli.amazonaws.com/AWSCLIV2-x86_64.pkg"
        ;;
      aarch64)
        DOWNLOAD_URL="https://awscli.amazonaws.com/AWSCLIV2-arm64.pkg"
        ;;
      *)
        DOWNLOAD_URL="https://awscli.amazonaws.com/AWSCLIV2.pkg"
        ;;
    esac
  fi

  printf "Downloading AWS CLI from $DOWNLOAD_URL...\\n"
  curl -fsSL "$DOWNLOAD_URL" -o /tmp/AWSCLIV2.pkg >> "${LOG_PATH}" 2>&1 || exit 1

  sudo installer -pkg /tmp/AWSCLIV2.pkg -target / >> "${LOG_PATH}" 2>&1 || exit 1

  rm -f /tmp/AWSCLIV2.pkg

else
  printf "Unsupported OS: $OS\\n" >> "${LOG_PATH}" 2>&1
  exit 1
fi

# Verify installation was successful
if command -v aws > /dev/null 2>&1; then
  printf "🥳 AWS CLI installed successfully!\\n"
  aws --version

  # Configure autocomplete for common shells
  if command -v aws_completer > /dev/null 2>&1; then
    AWS_COMPLETER_PATH=$(which aws_completer)

    # Bash autocomplete
    if [ -f ~/.bashrc ]; then
      if ! grep -q "aws_completer.*aws" ~/.bashrc; then
        echo "complete -C '$AWS_COMPLETER_PATH' aws" >> ~/.bashrc
        printf "✓ Configured AWS CLI autocomplete for bash\\n"
      fi
    fi

    # Zsh autocomplete
    if [ -f ~/.zshrc ] || [ -d ~/.oh-my-zsh ]; then
      if ! grep -q "aws_completer.*aws" ~/.zshrc 2> /dev/null; then
        cat >> ~/.zshrc << ZSHEOF

# AWS CLI autocomplete
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit
complete -C '$AWS_COMPLETER_PATH' aws
ZSHEOF
        printf "✓ Configured AWS CLI autocomplete for zsh\\n"
      fi
    fi

    # Fish autocomplete
    if [ -d ~/.config/fish ] || command -v fish > /dev/null 2>&1; then
      mkdir -p ~/.config/fish/completions
      FISH_COMPLETION=~/.config/fish/completions/aws.fish
      if [ ! -f "$FISH_COMPLETION" ]; then
        cat > "$FISH_COMPLETION" << 'FISHEOF'
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed '"'"'s/ $//'"'"'; end)'
FISHEOF
        printf "✓ Configured AWS CLI autocomplete for fish\\n"
      fi
    fi
  fi
else
  printf "❌ AWS CLI installation failed. Check logs at ${LOG_PATH}\\n"
  exit 1
fi
