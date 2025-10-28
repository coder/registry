#!/usr/bin/env bash

# Convert templated variables to shell variables
# This variable is assigned to itself, so the assignment does nothing.
# shellcheck disable=SC2269
LOG_PATH="${LOG_PATH}"

# Ports to listen on (comma/range); ignored for unix-sockets (default: 3923)
PORT="${PORT}"
# Pinned version (e.g., v1.19.16); overrides latest release discovery if set
PINNED_VERSION="${PINNED_VERSION}"
# Custom CLI Arguments# The variable from Terraform is a single, comma-separated string.
# We need to split it into a proper bash array using the comma (,) as the delimiter.
ARGUMENTS=(${ARGUMENTS})

# VARIABLE appears unused. Verify use (or export if used externally).
# shellcheck disable=SC2034
MODULE_NAME="Copyparty"

BOLD='\033[0;1m'

printf '%sInstalling %s ...\n' "${BOLD}" "$${MODULE_NAME}"

# Add code here
# Use variables from the templatefile function in main.tf
# e.g. LOG_PATH, PORT, etc.

printf "🐍 Verifying Python 3 installation...\n"
if ! command -v python3 &> /dev/null; then
  printf "❌ Python3 could not be found. Please install it to continue.\n"
  exit 1
fi
printf "✅ Python3 is installed.\n"

RELEASE_TO_INSTALL=""
# Install provided version to pin, otherwise discover latest github release from `https://github.com/9001/copyparty`.
if [[ -n "$${PINNED_VERSION}" ]]; then
  printf "📌 Pinned version specified: %s\n" "$${PINNED_VERSION}"
  # Verify that it is in v#.#.# format
  if [[ ! "$${PINNED_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf "❌ Invalid format for PINNED_VERSION. Expected 'v#.#.#' (e.g., v1.19.16).\n"
    exit 1
  fi
  RELEASE_TO_INSTALL="$${PINNED_VERSION}"
  printf "✅ Using pinned version %s.\n" "$${RELEASE_TO_INSTALL}"
else
  printf "🔎 Discovering latest release from GitHub...\n"
  # Use curl to get the latest release tag from the GitHub API and sed to parse it
  LATEST_RELEASE=$(curl -fsSL https://api.github.com/repos/9001/copyparty/releases/latest | grep '"tag_name":' | sed -E 's/.*"(v[^"]+)".*/\1/')
  if [[ -z "$${LATEST_RELEASE}" ]]; then
    printf "❌ Could not determine the latest release. Please check your internet connection.\n"
    exit 1
  fi
  RELEASE_TO_INSTALL="$${LATEST_RELEASE}"
  printf "🏷️  Latest release is %s.\n" "$${RELEASE_TO_INSTALL}"
fi

# Download appropriate release version assets: `copyparty-sfx.py` and `helptext.html`.
printf "🚀 Downloading copyparty v%s...\n" "$${RELEASE_TO_INSTALL}"
DOWNLOAD_URL="https://github.com/9001/copyparty/releases/download/$${RELEASE_TO_INSTALL}"

printf "⏬ Downloading copyparty-sfx.py...\n"
if ! curl -fsSL -o /tmp/copyparty-sfx.py "$${DOWNLOAD_URL}/copyparty-sfx.py"; then
  printf "❌ Failed to download copyparty-sfx.py.\n"
  exit 1
fi

printf "⏬ Downloading helptext.html...\n"
if ! curl -fsSL -o /tmp/helptext.html "$${DOWNLOAD_URL}/helptext.html"; then
  # This is not a fatal error, just a warning.
  printf "⚠️  Could not download helptext.html. The application will still work.\n"
fi

chmod +x /tmp/copyparty-sfx.py
printf "✅ Download complete.\n"

printf "🥳 Installation complete!\n"

# Build a clean, quoted string of the command for logging purposes only.
log_command="python3 /tmp/copyparty-sfx.py -p '$${PORT}'"
for arg in "$${ARGUMENTS[@]}"; do
  # printf "DEBUG: ARG [$${arg}]\n"
  log_command+=" '$${arg}'"
done

# Clear the log file and write the header and command string using printf.
{
  printf "=== Starting copyparty at %s ===\n" "$(date)"
  printf "EXECUTING: %s\n" "$${log_command}"
} > "/tmp/copyparty.cmd"

printf "👷 Starting %s in background...\n" "$${MODULE_NAME}"

# Execute the actual command using the robust array expansion.
# Then, append its output (stdout and stderr) to the log file.
python3 /tmp/copyparty-sfx.py -p "$${PORT}" "$${ARGUMENTS[@]}" > "$${LOG_PATH}" 2>&1 &

printf "✅ Service started. Check logs at %s\n" "$${LOG_PATH}"
