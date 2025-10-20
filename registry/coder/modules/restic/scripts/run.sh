#!/usr/bin/env bash
set -euo pipefail

: $${CODER_SCRIPT_BIN_DIR:=$HOME/.local/bin}
: $${CODER_SCRIPT_DATA_DIR:=$HOME/.local/share/coder}

mkdir -p "$CODER_SCRIPT_BIN_DIR"
mkdir -p "$CODER_SCRIPT_DATA_DIR"

export PATH="$HOME/.local/bin:$PATH"
INSTALL_RESTIC="${INSTALL_RESTIC}"
RESTIC_VERSION="${RESTIC_VERSION}"
AUTO_INIT="${AUTO_INIT}"
RESTORE_ON_START="${RESTORE_ON_START}"
SNAPSHOT_ID="${SNAPSHOT_ID}"
RESTORE_TARGET="${RESTORE_TARGET}"
BACKUP_INTERVAL="${BACKUP_INTERVAL}"
BACKUP_PATHS='${BACKUP_PATHS}'
EXCLUDE_PATTERNS='${EXCLUDE_PATTERNS}'
BACKUP_TAGS='${BACKUP_TAGS}'
DIRECTORY="${DIRECTORY}"
RETENTION_LAST="${RETENTION_LAST}"
RETENTION_DAILY="${RETENTION_DAILY}"
RETENTION_WEEKLY="${RETENTION_WEEKLY}"
RETENTION_MONTHLY="${RETENTION_MONTHLY}"
AUTO_FORGET="${AUTO_FORGET}"
AUTO_PRUNE="${AUTO_PRUNE}"
BACKUP_SCRIPT_B64='${BACKUP_SCRIPT_B64}'

echo "--------------------------------"
echo "Restic Backup Module Setup"
echo "--------------------------------"

detect_os_arch() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    x86_64)
      ARCH="amd64"
      ;;
    aarch64 | arm64)
      ARCH="arm64"
      ;;
    armv7l)
      ARCH="arm"
      ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  case "$OS" in
    linux | darwin) ;;
    *)
      echo "Unsupported OS: $OS"
      exit 1
      ;;
  esac

  echo "Detected OS: $OS, Architecture: $ARCH"
}

install_restic() {
  if [ "$INSTALL_RESTIC" != "true" ]; then
    echo "Skipping Restic installation (install_restic=false)"
    return
  fi

  if command -v restic > /dev/null 2>&1; then
    INSTALLED_VERSION=$(restic version | head -n1 | awk '{print $2}')
    echo "Restic already installed: $INSTALLED_VERSION"

    if [ "$RESTIC_VERSION" != "latest" ] && [ "$INSTALLED_VERSION" != "$RESTIC_VERSION" ]; then
      echo "Warning: Version mismatch (installed: $INSTALLED_VERSION, requested: $RESTIC_VERSION)"
    fi
    return
  fi

  echo "Installing Restic..."

  detect_os_arch

  if [ "$RESTIC_VERSION" = "latest" ]; then
    echo "Fetching latest version..."
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/restic/restic/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
      echo "Error: Failed to fetch latest version"
      exit 1
    fi

    echo "Version: $LATEST_VERSION"
    DOWNLOAD_URL="https://github.com/restic/restic/releases/download/v$${LATEST_VERSION}/restic_$${LATEST_VERSION}_$${OS}_$${ARCH}.bz2"
  else
    DOWNLOAD_URL="https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_$${OS}_$${ARCH}.bz2"
  fi

  echo "Downloading Restic..."

  mkdir -p "$HOME/.local/bin"

  TMP_FILE=$(mktemp)
  if curl -fsSL "$DOWNLOAD_URL" -o "$TMP_FILE"; then
    bunzip2 -c "$TMP_FILE" > "$HOME/.local/bin/restic"
    chmod +x "$HOME/.local/bin/restic"
    rm "$TMP_FILE"
    echo "Restic installed: $($HOME/.local/bin/restic version)"
  else
    echo "Error: Download failed"
    rm -f "$TMP_FILE"
    exit 1
  fi
}

verify_installation() {
  if ! command -v restic > /dev/null 2>&1; then
    echo "Error: restic command not found in PATH"
    echo "PATH: $PATH"

    if [ "$INSTALL_RESTIC" = "true" ]; then
      exit 1
    else
      echo "Warning: restic not found but install_restic=false, continuing anyway"
      return
    fi
  fi

  echo "Restic verified: $(restic version | head -n1)"
}

init_repository() {
  if [ "$AUTO_INIT" != "true" ]; then
    echo "Skipping repository initialization (auto_init_repo=false)"
    return
  fi

  echo "Checking repository..."

  if restic snapshots > /dev/null 2>&1; then
    echo "Repository already initialized"
    return
  fi

  echo "Initializing repository..."
  if restic init; then
    echo "Repository initialized"
  else
    echo "Error: Failed to initialize repository"
    exit 1
  fi
}

install_backup_helper() {
  echo "Installing backup helper script..."

  HELPER_SCRIPT="$CODER_SCRIPT_BIN_DIR/restic-backup"

  echo -n "$BACKUP_SCRIPT_B64" | base64 -d > "$HELPER_SCRIPT"
  chmod +x "$HELPER_SCRIPT"

  cat > "$CODER_SCRIPT_DATA_DIR/restic-backup.conf" << EOF
BACKUP_PATHS='$BACKUP_PATHS'
EXCLUDE_PATTERNS='$EXCLUDE_PATTERNS'
BACKUP_TAGS='$BACKUP_TAGS'
DIRECTORY='$DIRECTORY'
RETENTION_LAST='$RETENTION_LAST'
RETENTION_DAILY='$RETENTION_DAILY'
RETENTION_WEEKLY='$RETENTION_WEEKLY'
RETENTION_MONTHLY='$RETENTION_MONTHLY'
AUTO_FORGET='$AUTO_FORGET'
AUTO_PRUNE='$AUTO_PRUNE'
EOF

  if [ ! -x "$HELPER_SCRIPT" ]; then
    echo "Error: Backup helper is not executable"
    exit 1
  fi

  echo "Backup helper installed: $HELPER_SCRIPT"
  echo "Backup helper verified as executable"
}

find_latest_snapshot() {
  local TAG_FILTER="$1"

  SNAPSHOTS_JSON=$(restic snapshots --tag "$TAG_FILTER" --json 2> /dev/null || echo "[]")

  LATEST_SNAPSHOT=$(echo "$SNAPSHOTS_JSON" | python3 -c "
import json, sys
snapshots = json.load(sys.stdin)
if snapshots:
    latest = max(snapshots, key=lambda s: s['time'])
    print(latest['short_id'])
else:
    print('')
" 2> /dev/null || echo "")

  echo "$LATEST_SNAPSHOT"
}

restore_on_start() {
  if [ "$RESTORE_ON_START" != "true" ]; then
    echo "Skipping restore (restore_on_start=false)"
    return
  fi

  echo "--------------------------------"
  echo "Restore Configuration"
  echo "--------------------------------"

  SNAPSHOT_TO_RESTORE=""

  if [ -n "$SNAPSHOT_ID" ]; then
    echo "Restoring specific snapshot: $SNAPSHOT_ID"
    SNAPSHOT_TO_RESTORE="$SNAPSHOT_ID"
  else
    echo "Finding latest backup for this workspace..."
    SNAPSHOT_TO_RESTORE=$(find_latest_snapshot "workspace-id:$RESTIC_WORKSPACE_ID")

    if [ -z "$SNAPSHOT_TO_RESTORE" ]; then
      echo "No previous backup found"
      echo "Starting with fresh workspace"
      return
    fi

    echo "Found snapshot: $SNAPSHOT_TO_RESTORE"
  fi

  echo "Restoring to $RESTORE_TARGET..."

  if restic restore "$SNAPSHOT_TO_RESTORE" --target "$RESTORE_TARGET"; then
    echo "Restore completed successfully"
  else
    echo "Error: Restore failed"
    exit 1
  fi
}

setup_interval_backup() {
  if [ "$BACKUP_INTERVAL" -eq 0 ]; then
    return
  fi

  echo "Setting up interval backup (every $BACKUP_INTERVAL minutes)..."

  cat > "$CODER_SCRIPT_DATA_DIR/interval-backup.sh" << 'EOFSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

INTERVAL_MINUTES="$1"
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

echo "Starting interval backup loop (every $INTERVAL_MINUTES minutes)"

while true; do
  sleep "$INTERVAL_SECONDS"
  
  echo "Running scheduled backup..."
  if "$CODER_SCRIPT_BIN_DIR/restic-backup" --tag "interval-backup"; then
    echo "Scheduled backup completed"
  else
    echo "Scheduled backup failed"
  fi
done
EOFSCRIPT

  chmod +x "$CODER_SCRIPT_DATA_DIR/interval-backup.sh"

  nohup "$CODER_SCRIPT_DATA_DIR/interval-backup.sh" "$BACKUP_INTERVAL" \
    >> "$CODER_SCRIPT_DATA_DIR/interval-backup.log" 2>&1 &

  echo "Interval backup started in background (PID: $!)"
}

main() {
  install_restic
  verify_installation
  init_repository
  install_backup_helper
  restore_on_start
  setup_interval_backup

  echo "--------------------------------"
  echo "Restic setup complete"
  echo "--------------------------------"
  echo "Available commands:"
  echo "  restic-backup          - Run manual backup"
  echo "  restic snapshots       - List all snapshots"
  echo "  restic restore <id>    - Restore specific snapshot"
  echo ""
  echo "Repository: $${RESTIC_REPOSITORY:-not set}"
}

main
