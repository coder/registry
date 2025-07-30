#!/usr/bin/env sh

BOLD='\033[0;1m'

printf "$${BOLD}Installing jupyter-notebook!\n"

# check if jupyter-notebook is installed
if ! command -v jupyter-notebook > /dev/null 2>&1; then
  # install jupyter-notebook
  # check if pipx is installed
  if ! command -v pipx > /dev/null 2>&1; then
    echo "pipx is not installed"
    echo "Please install pipx in your Dockerfile/VM image before using this module"
    exit 1
  fi
  # install jupyter notebook
  pipx install --no-cache-dir -q notebook
  echo "🥳 jupyter-notebook has been installed\n\n"
else
  echo "🥳 jupyter-notebook is already installed\n\n"
fi

# Install packages selected with REQUIREMENTS_PATH
if [ -n "$REQUIREMENTS_PATH" ]; then
  if [ -f "$REQUIREMENTS_PATH" ]; then
    echo "📄 Installing packages from $REQUIREMENTS_PATH..."
    pip install --no-cache-dir -r "$REQUIREMENTS_PATH"
    echo "🥳 Requirements installed\n\n"
  else
    echo "⚠️  REQUIREMENTS_PATH is set to '$REQUIREMENTS_PATH' but the file does not exist!\n\n"
  fi
fi

# Install packages selected with PIP_INSTALL_PACKAGES
if [ -n "$PIP_INSTALL_PACKAGES" ]; then
  echo "📦 Installing extra pip packages: $PIP_INSTALL_PACKAGES"
  pip install --no-cache-dir $PIP_INSTALL_PACKAGES
  echo "🥳 Extra packages installed\n\n"
fi

echo "👷 Starting jupyter-notebook in background..."
echo "check logs at ${LOG_PATH}"
$HOME/.local/bin/jupyter-notebook --NotebookApp.ip='0.0.0.0' --ServerApp.port=${PORT} --no-browser --ServerApp.token='' --ServerApp.password='' > ${LOG_PATH} 2>&1 &
