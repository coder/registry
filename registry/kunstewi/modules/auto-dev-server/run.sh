#!/usr/bin/env bash

# Exit on error, treat unset variables as an error, and propagate exit status through pipes.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"
PACKAGE_JSON_PATH="$PROJECT_DIR/package.json"
LOG_FILE="$PROJECT_DIR/auto-npm-start.log"
PID_FILE="$PROJECT_DIR/.auto-npm-start.pid"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "npm could not be found. Skipping auto-start."
    exit 0
fi

# Check if the project directory and package.json exist
if [ ! -f "$PACKAGE_JSON_PATH" ]; then
    echo "No package.json found in $PROJECT_DIR. Skipping auto-start."
    exit 0
fi

# Check if a server is already running from a previous start
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    # Check if the process with that PID is still running
    if ps -p "$PID" > /dev/null; then
        echo "Server is already running with PID $PID. Skipping."
        exit 0
    else
        echo "PID file found, but process $PID is not running. Cleaning up."
        rm "$PID_FILE"
    fi
fi

echo "package.json found. Starting development server in the background..."
echo "Log file will be at: $LOG_FILE"

# Change to the project directory, run npm start in the background, and store its PID.
(cd "$PROJECT_DIR" && nohup npm start > "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE")

echo "Server start command issued. Check log for details."

