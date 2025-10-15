#!/usr/bin/env bash
set -euo pipefail

LIB_B64="${TF_LIB_B64}"
EXTRACT_ON_START="${TF_EXTRACT_ON_START}"
EXTRACT_WAIT_TIMEOUT="${TF_EXTRACT_WAIT_TIMEOUT}"

# Set script defaults from Terraform.
DEFAULT_PATHS=(${TF_PATHS})
DEFAULT_EXCLUDE_PATTERNS=(${TF_EXCLUDE_PATTERNS})
DEFAULT_COMPRESSION="${TF_COMPRESSION}"
DEFAULT_ARCHIVE_PATH="${TF_ARCHIVE_PATH}"
DEFAULT_DIRECTORY="${TF_DIRECTORY}"

# 1) Decode the library into $CODER_SCRIPT_DATA_DIR/archive-lib.sh (static, sourceable).
LIB_PATH="$CODER_SCRIPT_DATA_DIR/archive-lib.sh"
lib_tmp="$(mktemp -t coder-module-archive.XXXXXX))"
trap 'rm -f "$lib_tmp" 2>/dev/null || true' EXIT

# Decode the base64 content safely.
if ! printf '%s' "$LIB_B64" | base64 -d > "$lib_tmp"; then
  echo "ERROR: Failed to decode archive library from base64." >&2
  exit 1
fi
chmod 0644 "$lib_tmp"
mv "$lib_tmp" "$LIB_PATH"

# 2) Generate the wrapper scripts (create and extract).
create_wrapper() {
  tmp="$(mktemp -t coder-module-archive.XXXXXX)"
  trap 'rm -f "$tmp" 2>/dev/null || true' EXIT
  cat > "$tmp" << EOF
#!/usr/bin/env bash
set -euo pipefail

. "$LIB_PATH"

# Set defaults from Terraform (through installer).
$(
    declare -p \
      DEFAULT_PATHS \
      DEFAULT_EXCLUDE_PATTERNS \
      DEFAULT_COMPRESSION \
      DEFAULT_ARCHIVE_PATH \
      DEFAULT_DIRECTORY
  )

$1 "\$@"
EOF
  chmod 0755 "$tmp"
  mv "$tmp" "$2"
}

CREATE_WRAPPER_PATH="$CODER_SCRIPT_BIN_DIR/coder-archive-create"
EXTRACT_WRAPPER_PATH="$CODER_SCRIPT_BIN_DIR/coder-archive-extract"
create_wrapper archive_create "$CREATE_WRAPPER_PATH"
create_wrapper archive_extract "$EXTRACT_WRAPPER_PATH"

echo "Installed archive library to: $LIB_PATH"
echo "Installed create script to:   $CREATE_WRAPPER_PATH"
echo "Installed extract script to:  $EXTRACT_WRAPPER_PATH"

# 3) Optionally wait for and extract an archive on start.
if [[ $EXTRACT_ON_START = true ]]; then
  . "$LIB_PATH"

  archive_wait_and_extract "$EXTRACT_WAIT_TIMEOUT" quiet || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      echo "WARNING: Archive not found in backup path (this is expected with new workspaces)."
    else
      exit $exit_code
    fi
  }
fi
