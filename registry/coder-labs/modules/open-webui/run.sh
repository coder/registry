#!/usr/bin/env sh

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
  echo "❌ Python 3.11 or higher is not installed"
  echo ""
  echo "Installing Python 3.11 from deadsnakes PPA..."
  
  # Check if we have sudo access
  if ! command -v sudo > /dev/null 2>&1; then
    echo "❌ sudo is not available. Please install Python 3.11+ manually"
    exit 1
  fi
  
  # Install Python 3.11
  echo "📦 Adding deadsnakes PPA..."
  sudo apt-get update -qq
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
  
  echo "📦 Installing Python 3.11..."
  sudo apt-get install -y python3.11 python3.11-venv python3.11-dev
  
  PYTHON_CMD="python3.11"
  echo "✅ Python 3.11 installed successfully"
fi

# Check if pip is available
if ! "$PYTHON_CMD" -m pip --version > /dev/null 2>&1; then
  echo "📦 Installing pip..."
  curl -sS https://bootstrap.pypa.io/get-pip.py | "$PYTHON_CMD"
fi

# Check if open-webui is already installed
if ! "$PYTHON_CMD" -m pip show open-webui > /dev/null 2>&1; then
  echo "📦 Installing Open WebUI..."
  "$PYTHON_CMD" -m pip install --user open-webui
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
"$PYTHON_CMD" -m open_webui serve --host 0.0.0.0 --port "$PORT" > "$LOG_PATH" 2>&1 &

# Wait a bit for the server to start
sleep 2

echo "🥳 Open WebUI is starting!"
echo "Access it at http://localhost:$PORT"
