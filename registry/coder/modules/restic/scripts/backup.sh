#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="$CODER_SCRIPT_DATA_DIR/restic-backup.conf"
if [ -f "$CONF_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONF_FILE"
else
  echo "Error: Configuration file not found: $CONF_FILE" >&2
  exit 1
fi

EXTRA_TAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      EXTRA_TAGS+=("$2")
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: restic-backup [--tag TAG]" >&2
      exit 1
      ;;
  esac
done

echo "--------------------------------"
echo "Restic Backup"
echo "--------------------------------"

DIRECTORY="${DIRECTORY/#\~/$HOME}"

PATHS=$(echo "$BACKUP_PATHS" | python3 -c "import json, sys; print(' '.join(json.load(sys.stdin)))" 2> /dev/null || echo ".")
EXCLUDES=$(echo "$EXCLUDE_PATTERNS" | python3 -c "import json, sys; [print(f'--exclude={p}') for p in json.load(sys.stdin)]" 2> /dev/null || echo "")
TAGS=$(echo "$BACKUP_TAGS" | python3 -c "import json, sys; [print(f'--tag={t}') for t in json.load(sys.stdin)]" 2> /dev/null || echo "")

TAG_ARGS=(
  "--tag=workspace-id:$RESTIC_WORKSPACE_ID"
  "--tag=workspace-owner:$RESTIC_WORKSPACE_OWNER"
  "--tag=workspace-name:$RESTIC_WORKSPACE_NAME"
)

if [ -n "$TAGS" ]; then
  while IFS= read -r tag; do
    [ -n "$tag" ] && TAG_ARGS+=("$tag")
  done <<< "$TAGS"
fi

for tag in "${EXTRA_TAGS[@]}"; do
  TAG_ARGS+=("--tag=$tag")
done

EXCLUDE_ARGS=()
if [ -n "$EXCLUDES" ]; then
  while IFS= read -r exclude; do
    [ -n "$exclude" ] && EXCLUDE_ARGS+=("$exclude")
  done <<< "$EXCLUDES"
fi

cd "$DIRECTORY" || {
  echo "Error: Failed to change to directory: $DIRECTORY" >&2
  exit 1
}

echo "Working directory: $(pwd)"
echo "Backup paths: $PATHS"
echo "Tags: ${TAG_ARGS[*]}"
[ ${#EXCLUDE_ARGS[@]} -gt 0 ] && echo "Exclusions: ${EXCLUDE_ARGS[*]}"
echo "Starting backup..."

# shellcheck disable=SC2086
if restic backup $PATHS "${TAG_ARGS[@]}" "${EXCLUDE_ARGS[@]}"; then
  echo "Backup completed successfully"
else
  echo "Error: Backup failed" >&2
  exit 1
fi

if [ "$AUTO_FORGET" = "true" ]; then
  echo "Applying retention policies..."

  FORGET_ARGS=(
    "--tag=workspace-id:$RESTIC_WORKSPACE_ID"
    "--keep-last=$RETENTION_LAST"
  )

  [ "$RETENTION_DAILY" -gt 0 ] && FORGET_ARGS+=("--keep-daily=$RETENTION_DAILY")
  [ "$RETENTION_WEEKLY" -gt 0 ] && FORGET_ARGS+=("--keep-weekly=$RETENTION_WEEKLY")
  [ "$RETENTION_MONTHLY" -gt 0 ] && FORGET_ARGS+=("--keep-monthly=$RETENTION_MONTHLY")

  if [ "$AUTO_PRUNE" = "true" ]; then
    FORGET_ARGS+=("--prune")
    echo "Pruning unreferenced data..."
  fi

  if restic forget "${FORGET_ARGS[@]}"; then
    echo "Retention policies applied"
  else
    echo "Warning: Failed to apply retention policies" >&2
  fi
fi

echo "Backup process complete"
