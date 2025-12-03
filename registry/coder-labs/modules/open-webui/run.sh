#!/usr/bin/env sh
set -e

# shellcheck disable=SC2059
printf '\033[0;1mInstalling Open WebUI...\n\n'

# Function to check Python version
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

# Find suitable Python version
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

# Set up virtual environment
VENV_DIR="$HOME/.open-webui-venv"
if [ ! -d "$VENV_DIR" ]; then
  echo "📦 Creating virtual environment..."
  "$PYTHON_CMD" -m venv "$VENV_DIR"
fi

# Activate virtual environment
# shellcheck disable=SC1091
. "$VENV_DIR/bin/activate"

# Check if open-webui is already installed
if ! pip show open-webui > /dev/null 2>&1; then
  echo "📦 Installing Open WebUI..."
  pip install open-webui
  echo "🥳 Open WebUI has been installed"
else
  echo "✅ Open WebUI is already installed"
fi

# Check if Open WebUI is already running
if pgrep -f "open-webui serve" > /dev/null; then
  echo "✅ Open WebUI is already running"
  exit 0
fi

echo "👷 Starting Open WebUI in background..."
echo "Check logs at $LOG_PATH"

# Start Open WebUI
open-webui serve --host 0.0.0.0 --port "$PORT" > "$LOG_PATH" 2>&1 &

# Wait a bit for the server to start
sleep 2

echo "🥳 Open WebUI is starting!"
echo "Access it at http://localhost:$PORT"
