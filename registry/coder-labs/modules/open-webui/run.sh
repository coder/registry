#!/usr/bin/env sh

set -eu

printf '\033[0;1mInstalling Open WebUI %s...\n\n' "${VERSION}"

check_python_version() {
  python_cmd="$1"
  if command -v "$python_cmd" > /dev/null 2>&1; then
    version=$("$python_cmd" --version 2>&1 | awk '{print $2}')
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    if [ "$major" -eq 3 ] && [ "$minor" -ge 11 ]; then
      echo "$python_cmd"
      return 0
    fi
  fi
  return 1
}

PYTHON_CMD=""
for cmd in python3.13 python3.12 python3.11 python3 python; do
  if result=$(check_python_version "$cmd"); then
    PYTHON_CMD="$result"
    echo "✅ Found suitable Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"
    break
  fi
done

if [ -z "$PYTHON_CMD" ]; then
  echo "❌ Python 3.11 or higher is required but not found."
  echo ""
  echo "Please install Python 3.11+ in your image. For example on Ubuntu/Debian:"
  echo "  sudo add-apt-repository -y ppa:deadsnakes/ppa"
  echo "  sudo apt-get update"
  echo "  sudo apt-get install -y python3.11 python3.11-venv"
  exit 1
fi

VENV_DIR="$HOME/.open-webui-venv"
if [ ! -d "$VENV_DIR" ]; then
  echo "📦 Creating virtual environment..."
  "$PYTHON_CMD" -m venv "$VENV_DIR"
fi
. "$VENV_DIR/bin/activate"

if ! pip show open-webui > /dev/null 2>&1; then
  echo "📦 Installing Open WebUI version ${VERSION}..."
  pip install "open-webui==${VERSION}"
  echo "🥳 Open WebUI has been installed"
else
  echo "✅ Open WebUI is already installed"
fi

echo "👷 Starting Open WebUI in background..."
echo "Check logs at ${HTTP_SERVER_LOG_PATH}"

echo "DATA_DIR: ${DATA_DIR}"

# Export OpenAI API key if provided
if [ -n "${OPENAI_API_KEY}" ]; then
  export OPENAI_API_KEY="${OPENAI_API_KEY}"
  echo "🔑 OpenAI API key configured"
fi

open-webui serve --host 0.0.0.0 --port "${HTTP_SERVER_PORT}" > "${HTTP_SERVER_LOG_PATH}" 2>&1 &

echo "🥳 Open WebUI is ready. HTTP server is listening on port ${HTTP_SERVER_PORT}"
