#!/usr/bin/env sh
# shellcheck disable=SC2292
# SC2292: We use [ ] instead of [[ ]] for POSIX sh compatibility.
set -eu

error() {
  printf "ERROR: %s\n" "$@"
  exit 1
}

# Check if portabledesktop is already in PATH.
if command -v portabledesktop > /dev/null 2>&1; then
  printf "portabledesktop is already installed and in PATH.\n"
  exit 0
fi

# Determine the storage path.
STORAGE_DIR="${CODER_SCRIPT_DATA_DIR}"
BINARY_PATH="${STORAGE_DIR}/portabledesktop"
mkdir -p "${STORAGE_DIR}"

# If the binary already exists and is executable, skip download.
if [ -x "${BINARY_PATH}" ]; then
  printf "portabledesktop is already installed at %s, skipping download.\n" "${BINARY_PATH}"
else
  # Detect architecture and select the appropriate download URL.
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64)
      URL="${ARG_AMD64_URL}"
      ;;
    aarch64)
      URL="${ARG_ARM64_URL}"
      ;;
    *)
      error "Unsupported architecture: ${ARCH}"
      ;;
  esac

  # Select download tool.
  if command -v curl > /dev/null 2>&1; then
    DOWNLOAD_CMD="curl"
  elif command -v wget > /dev/null 2>&1; then
    DOWNLOAD_CMD="wget"
  else
    error "No download tool available (curl or wget required)."
  fi

  # Download with retry loop (3 attempts, 1s sleep between).
  TMPFILE=$(mktemp)
  MAX_ATTEMPTS=3
  DOWNLOAD_SUCCESS=false
  ATTEMPT=1

  while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
    printf "Downloading portabledesktop (attempt %s/%s) via %s...\n" "${ATTEMPT}" "${MAX_ATTEMPTS}" "${DOWNLOAD_CMD}"

    DOWNLOAD_OK=false
    if [ "${DOWNLOAD_CMD}" = "curl" ]; then
      curl -fsSL "${URL}" -o "${TMPFILE}" && DOWNLOAD_OK=true
    else
      wget -qO "${TMPFILE}" "${URL}" && DOWNLOAD_OK=true
    fi

    if [ "${DOWNLOAD_OK}" = "true" ]; then
      # Verify checksum when ARG_SHA256 is non-empty.
      if [ -n "${ARG_SHA256}" ]; then
        CHECKSUM_MATCH=false
        if command -v sha256sum > /dev/null 2>&1; then
          echo "${ARG_SHA256}  ${TMPFILE}" | sha256sum -c - > /dev/null 2>&1 && CHECKSUM_MATCH=true
        elif command -v shasum > /dev/null 2>&1; then
          echo "${ARG_SHA256}  ${TMPFILE}" | shasum -a 256 -c - > /dev/null 2>&1 && CHECKSUM_MATCH=true
        else
          rm -f "${TMPFILE}"
          error "No SHA256 tool available (sha256sum or shasum required)."
        fi

        if [ "${CHECKSUM_MATCH}" != "true" ]; then
          printf "WARNING: Checksum mismatch (attempt %s/%s): expected %s\n" \
            "${ATTEMPT}" "${MAX_ATTEMPTS}" "${ARG_SHA256}"
          rm -f "${TMPFILE}"
          if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
            sleep 1
          fi
          ATTEMPT=$((ATTEMPT + 1))
          continue
        fi
        printf "Checksum verified successfully.\n"
      fi

      DOWNLOAD_SUCCESS=true
      break
    else
      printf "WARNING: Download failed (attempt %s/%s).\n" "${ATTEMPT}" "${MAX_ATTEMPTS}"
      if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
        sleep 1
      fi
    fi

    ATTEMPT=$((ATTEMPT + 1))
  done

  if [ "${DOWNLOAD_SUCCESS}" != "true" ]; then
    rm -f "${TMPFILE}"
    error "Failed to download portabledesktop after ${MAX_ATTEMPTS} attempts."
  fi

  # Make the binary executable and move to storage path.
  chmod 755 "${TMPFILE}"
  mv "${TMPFILE}" "${BINARY_PATH}"
fi

# Symlink into CODER_SCRIPT_BIN_DIR for PATH access.
if [ -n "${CODER_SCRIPT_BIN_DIR}" ] && [ ! -e "${CODER_SCRIPT_BIN_DIR}/portabledesktop" ]; then
  ln -s "${CODER_SCRIPT_DATA_DIR}/portabledesktop" "${CODER_SCRIPT_BIN_DIR}/portabledesktop"
fi

# If ARG_INSTALL_DIR is set, copy the binary there with sudo fallback.
if [ -n "${ARG_INSTALL_DIR}" ]; then
  if [ ! -d "${ARG_INSTALL_DIR}" ]; then
    mkdir -p "${ARG_INSTALL_DIR}" 2> /dev/null || sudo mkdir -p "${ARG_INSTALL_DIR}" 2> /dev/null || true
  fi
  if cp "${CODER_SCRIPT_DATA_DIR}/portabledesktop" "${ARG_INSTALL_DIR}/portabledesktop" 2> /dev/null; then
    printf "Copied portabledesktop to %s.\n" "${ARG_INSTALL_DIR}/portabledesktop"
  elif sudo cp "${CODER_SCRIPT_DATA_DIR}/portabledesktop" "${ARG_INSTALL_DIR}/portabledesktop" 2> /dev/null; then
    printf "Copied portabledesktop to %s (via sudo).\n" "${ARG_INSTALL_DIR}/portabledesktop"
  else
    error "Failed to copy portabledesktop to ${ARG_INSTALL_DIR}/portabledesktop."
  fi
fi

printf "portabledesktop installed successfully.\n"
