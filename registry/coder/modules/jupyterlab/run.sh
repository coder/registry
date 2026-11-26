#!/usr/bin/env bash
set -e

INSTALLER=""
check_available_installer() {
  # check if pipx is installed
  echo "Checking for a supported installer"
  if command -v pipx > /dev/null 2>&1; then
    echo "pipx is installed"
    INSTALLER="pipx"
    return
  fi
  # check if uv is installed
  if command -v uv > /dev/null 2>&1; then
    echo "uv is installed"
    INSTALLER="uv"
    return
  fi
  echo "No supported installer found."
  echo "Please install pipx or uv in your Dockerfile/VM image before running this script"
  exit 1
}

BOLD='\033[0;1m'

# check if jupyterlab is installed
if ! command -v jupyter-lab > /dev/null 2>&1; then
  # install jupyterlab
  check_available_installer
  printf "$${BOLD}Installing jupyterlab!\n"
  case $INSTALLER in
    uv)
      uv pip install -q jupyterlab
      printf "%s\n" "🥳 jupyterlab has been installed"
      JUPYTER="$HOME/.venv/bin/jupyter-lab"
      ;;
    pipx)
      pipx install jupyterlab
      printf "%s\n" "🥳 jupyterlab has been installed"
      JUPYTER="$(pipx environment --value PIPX_BIN_DIR)/jupyter-lab"
      ;;
  esac
else
  printf "%s\n\n" "🥳 jupyterlab is already installed"
  JUPYTER=$(command -v jupyter-lab)
fi

# pipx shares the pip library but does not create a pip executable in the venv.
# Keep notebook !pip commands in the same environment as the default kernel,
# including workspaces where JupyterLab was installed before this module ran.
if command -v pipx > /dev/null 2>&1; then
  PIPX_JUPYTER_BIN="$(pipx environment --value PIPX_LOCAL_VENVS)/jupyterlab/bin"
  if [ "$(readlink -f "$JUPYTER")" = "$PIPX_JUPYTER_BIN/jupyter-lab" ]; then
    if [ ! -x "$PIPX_JUPYTER_BIN/pip" ]; then
      pipx inject jupyterlab pip --pip-args=--ignore-installed
    fi
    export PATH="$PIPX_JUPYTER_BIN:$PATH"
  fi
fi

mkdir -p "$(dirname "${LOG_PATH}")"
printf "👷 Starting jupyterlab in background..."
printf '%s\n' "check logs at ${LOG_PATH}"
"$JUPYTER" --no-browser \
  --ServerApp.base_url=${BASE_URL} \
  --ServerApp.ip='${HOST}' \
  --ServerApp.port='${PORT}' \
  --ServerApp.allow_remote_access=True \
  --ServerApp.token='' \
  --ServerApp.password='' \
  > "${LOG_PATH}" 2>&1 &
