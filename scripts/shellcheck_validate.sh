#!/usr/bin/env bash

set -euo pipefail

# Auto-detect which shell scripts to validate based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   SHELL_CHANGED_FILES - only .sh files (for processing)
# Validates all shell scripts if shared infrastructure changes
#
# This script validates all shell scripts across the repository

validate_shell_script() {
  local file="$1"
  echo "Validating $file"

  # Run shellcheck with warning severity level
  # Using gcc format for better IDE/editor integration
  if ! shellcheck --severity=warning --format=gcc "$file"; then
    return 1
  fi
  return 0
}

main() {
  echo "==> Detecting changed files..."

  if [[ -n "${ALL_CHANGED_FILES:-}" ]]; then
    echo "Changed files in PR:"
    echo "$ALL_CHANGED_FILES" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""
  fi

  # Determine which files to check
  local files_to_check=()

  if [[ "${SHARED_CHANGED:-false}" == "true" ]]; then
    echo "==> Shared infrastructure changed"
    echo "==> Validating all shell scripts for safety"

    # Find all .sh files in the repository, excluding node_modules and .git
    mapfile -t files_to_check < <(find . -type f -name "*.sh" ! -path "*/node_modules/*" ! -path "*/.git/*" | sort)
  elif [[ -z "${SHELL_CHANGED_FILES:-}" ]]; then
    echo "✓ No shell script files changed, skipping validation"
    exit 0
  else
    # Process only changed shell scripts
    CHANGED_FILES=$(echo "$SHELL_CHANGED_FILES" | tr ' ' '\n')

    while IFS= read -r file; do
      if [[ -f "$file" && "$file" == *.sh ]]; then
        files_to_check+=("$file")
      fi
    done <<< "$CHANGED_FILES"
  fi

  if [[ ${#files_to_check[@]} -eq 0 ]]; then
    echo "✓ No shell scripts to validate"
    exit 0
  fi

  echo "==> Validating ${#files_to_check[@]} shell script(s):"
  for file in "${files_to_check[@]}"; do
    echo "  - $file"
  done
  echo ""

  # Validate each file
  local status=0
  local failed_files=()

  for file in "${files_to_check[@]}"; do
    if ! validate_shell_script "$file"; then
      status=1
      failed_files+=("$file")
    fi
  done

  # Report results
  if [[ $status -eq 0 ]]; then
    echo ""
    echo "✓ All shell scripts passed validation"
  else
    echo ""
    echo "❌ ShellCheck validation failed for ${#failed_files[@]} file(s):"
    for file in "${failed_files[@]}"; do
      echo "  - $file"
    done
  fi

  exit $status
}

main
