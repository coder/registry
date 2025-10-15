#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$@" >&2
}
warn() {
  printf 'WARNING: %s\n' "$1" >&2
}
error() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

load_defaults() {
  DEFAULT_PATHS=("${DEFAULT_PATHS[@]:-.}")
  DEFAULT_EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]:-}")
  DEFAULT_COMPRESSION="${DEFAULT_COMPRESSION:-gzip}"
  DEFAULT_ARCHIVE_PATH="${DEFAULT_ARCHIVE_PATH:-/tmp/coder-archive.tar.gz}"
  DEFAULT_DIRECTORY="${DEFAULT_DIRECTORY:-$HOME}"
}

ensure_tools() {
  command -v tar > /dev/null 2>&1 || error "tar is required"
  case "$1" in
    gzip)
      command -v gzip > /dev/null 2>&1 || error "gzip is required for gzip compression"
      ;;
    zstd)
      command -v zstd > /dev/null 2>&1 || error "zstd is required for zstd compression"
      ;;
    none) ;;
    *)
      error "Unsupported compression algorithm: $1"
      ;;
  esac
}

usage_archive_create() {
  load_defaults

  cat >&2 << USAGE
Usage: coder-create-archive [OPTIONS] [[PATHS] ...]
Options:
  -c, --compression <gzip|zstd|none>   Compression algorithm (default "${DEFAULT_COMPRESSION}")
  -C, --directory <DIRECTORY>          Change to directory (default "${DEFAULT_DIRECTORY}")
  -f, --file <ARCHIVE>                 Output archive file (default "${DEFAULT_ARCHIVE_PATH}")
  -h, --help                           Show this help
USAGE
}

archive_create() {
  load_defaults

  local compression="${DEFAULT_COMPRESSION}"
  local directory="${DEFAULT_DIRECTORY}"
  local file="${DEFAULT_ARCHIVE_PATH}"
  local paths=("${DEFAULT_PATHS[@]}")

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c | --compression)
        if [[ $# -lt 2 ]]; then
          usage_archive_create
          error "Missing value for $1"
        fi
        compression="$2"
        shift 2
        ;;
      -C | --directory)
        if [[ $# -lt 2 ]]; then
          usage_archive_create
          error "Missing value for $1"
        fi
        directory="$2"
        shift 2
        ;;
      -f | --file)
        if [[ $# -lt 2 ]]; then
          usage_archive_create
          error "Missing value for $1"
        fi
        file="$2"
        shift 2
        ;;
      -h | --help)
        usage_archive_create
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          paths+=("$1")
          shift
        done
        ;;
      -*)
        usage_archive_create
        error "Unknown option: $1"
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  ensure_tools "$compression"

  local -a tar_opts=(-c -f "$file" -C "$directory")
  case "$compression" in
    gzip)
      tar_opts+=(-z)
      ;;
    zstd)
      tar_opts+=(--zstd)
      ;;
    none) ;;
    *)
      error "Unsupported compression algorithm: $compression"
      ;;
  esac

  for path in "${DEFAULT_EXCLUDE_PATTERNS[@]}"; do
    if [[ -n $path ]]; then
      tar_opts+=(--exclude "$path")
    fi
  done

  # Ensure destination directory exists.
  dest="$(dirname "$file")"
  mkdir -p "$dest" 2> /dev/null || error "Failed to create output dir: $dest"

  log "Creating archive:"
  log "  Compression: $compression"
  log "  Directory:   $directory"
  log "  Archive:     $file"
  log "  Paths:       ${paths[*]}"
  log "  Exclude:     ${DEFAULT_EXCLUDE_PATTERNS[*]}"

  umask 077
  tar "${tar_opts[@]}" "${paths[@]}"

  printf '%s\n' "$file"
}

usage_archive_extract() {
  load_defaults

  cat >&2 << USAGE
Usage: coder-extract-archive [OPTIONS]
Options:
  -c, --compression <gzip|zstd|none>   Compression algorithm (default "${DEFAULT_COMPRESSION}")
  -C, --directory <DIRECTORY>          Change to directory (default "${DEFAULT_DIRECTORY}")
  -f, --file <ARCHIVE>                 Output archive file (default "${DEFAULT_ARCHIVE_PATH}")
  -h, --help                           Show this help
USAGE
}

archive_extract() {
  load_defaults

  local compression="${DEFAULT_COMPRESSION}"
  local directory="${DEFAULT_DIRECTORY}"
  local file="${DEFAULT_ARCHIVE_PATH}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c | --compression)
        if [[ $# -lt 2 ]]; then
          usage_archive_extract
          error "Missing value for $1"
        fi
        compression="$2"
        shift 2
        ;;
      -C | --directory)
        if [[ $# -lt 2 ]]; then
          usage_archive_extract
          error "Missing value for $1"
        fi
        directory="$2"
        shift 2
        ;;
      -f | --file)
        if [[ $# -lt 2 ]]; then
          usage_archive_extract
          error "Missing value for $1"
        fi
        file="$2"
        shift 2
        ;;
      -h | --help)
        usage_archive_extract
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          shift
        done
        ;;
      -*)
        usage_archive_extract
        error "Unknown option: $1"
        ;;
      *)
        shift
        ;;
    esac
  done

  ensure_tools "$compression"

  local -a tar_opts=(-x -f "$file" -C "$directory")
  case "$compression" in
    gzip)
      tar_opts+=(-z)
      ;;
    zstd)
      tar_opts+=(--zstd)
      ;;
    none) ;;
    *)
      error "Unsupported compression algorithm: $compression"
      ;;
  esac

  for path in "${DEFAULT_EXCLUDE_PATTERNS[@]}"; do
    if [[ -n $path ]]; then
      tar_opts+=(--exclude "$path")
    fi
  done

  # Ensure destination directory exists.
  mkdir -p "$directory" || error "Failed to create directory: $directory"

  log "Extracting archive:"
  log "  Compression: $compression"
  log "  Directory:   $directory"
  log "  Archive:     $file"
  log "  Exclude:     ${DEFAULT_EXCLUDE_PATTERNS[*]}"

  umask 077
  tar "${tar_opts[@]}" "${paths[@]}"

  printf 'Extracted %s into %s\n' "$file" "$directory"
}

archive_wait_and_extract() {
  load_defaults

  local timeout="${1:-300}"
  local quiet="${2:-}"
  local file="${DEFAULT_ARCHIVE_PATH}"

  local start now
  start=$(date +%s)
  while true; do
    if [[ -f "$file" ]]; then
      archive_extract -f "$file"
      return 0
    fi

    if ((timeout <= 0)); then
      break
    fi
    now=$(date +%s)
    if ((now - start >= timeout)); then
      break
    fi
    sleep 5
  done

  if [[ -z $quiet ]]; then
    printf 'ERROR: Timed out waiting for archive: %s\n' "$file" >&2
  fi
  return 2
}
