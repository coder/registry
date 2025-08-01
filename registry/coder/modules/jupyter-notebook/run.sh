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
  pipx install -q notebook
  echo "🥳 jupyter-notebook has been installed\n\n"
else
  echo "🥳 jupyter-notebook is already installed\n\n"
fi

# Install packages selected with REQUIREMENTS_PATH
if [ -n "${REQUIREMENTS_PATH}" ]; then
  if [ -f "${REQUIREMENTS_PATH}" ]; then
    echo "📄 Installing packages from ${REQUIREMENTS_PATH}..."
    pipx -q runpip notebook install -r "${REQUIREMENTS_PATH}"
    echo "🥳 Packages from ${REQUIREMENTS_PATH} have been installed\n\n"
  else
    echo "⚠️  REQUIREMENTS_PATH is set to '${REQUIREMENTS_PATH}' but the file does not exist!\n\n"
  fi
fi

# Install packages selected with PIP_INSTALL_EXTRA_PACKAGES
if [ -n "${PIP_INSTALL_EXTRA_PACKAGES}" ]; then
  echo "📦 Installing additional packages: ${PIP_INSTALL_EXTRA_PACKAGES}"
  pipx -q runpip notebook install ${PIP_INSTALL_EXTRA_PACKAGES}
  echo "🥳 Additional packages have been installed\n\n"
fi

echo "👷 Starting jupyter-notebook in background..."
echo "check logs at ${LOG_PATH}"
$HOME/.local/bin/jupyter-notebook --NotebookApp.ip='0.0.0.0' --ServerApp.port=${PORT} --no-browser --ServerApp.token='' --ServerApp.password='' > ${LOG_PATH} 2>&1 &
