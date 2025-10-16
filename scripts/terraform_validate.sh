#!/bin/bash

set -euo pipefail

# Auto-detect which Terraform modules to validate based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
# Validates all modules if shared infrastructure changes or if env vars are not set (local dev)
#
# This script only validates changed modules. Documentation and template changes are ignored.

validate_terraform_directory() {
  local dir="$1"
  echo "Running \`terraform validate\` in $dir"
  pushd "$dir"
  terraform init -upgrade
  terraform validate
  popd
}

main() {
  echo "==> Detecting changed files..."

  if [[ -n "${ALL_CHANGED_FILES:-}" ]]; then
    echo "Changed files in PR:"
    echo "$ALL_CHANGED_FILES" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""
  fi

  local script_dir=$(dirname "$(readlink -f "$0")")
  local registry_dir="$script_dir/../registry"

  if [[ "${SHARED_CHANGED:-false}" == "true" ]]; then
    echo "==> Shared infrastructure changed"
    echo "==> Validating all modules for safety"
    local subdirs=$(find "$registry_dir" -mindepth 3 -path "*/modules/*" -type d | sort)
  elif [[ -z "${MODULE_CHANGED_FILES:-}" ]]; then
    echo "✓ No module files changed, skipping validation"
    exit 0
  else
    CHANGED_FILES=$(echo "$MODULE_CHANGED_FILES" | tr ' ' '\n')

    MODULE_DIRS=()
    while IFS= read -r file; do
      if [[ "$file" =~ \.(md|png|jpg|jpeg|svg)$ ]]; then
        continue
      fi

      if [[ "$file" =~ ^registry/([^/]+)/modules/([^/]+)/ ]]; then
        namespace="${BASH_REMATCH[1]}"
        module="${BASH_REMATCH[2]}"
        module_dir="registry/${namespace}/modules/${module}"

        if [[ -d "$module_dir" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " ${module_dir} " ]]; then
          MODULE_DIRS+=("$module_dir")
        fi
      fi
    done <<< "$CHANGED_FILES"

    if [[ ${#MODULE_DIRS[@]} -eq 0 ]]; then
      echo "✓ No modules to validate"
      echo "  (documentation, templates, namespace files, or modules without changes)"
      exit 0
    fi

    echo "==> Validating ${#MODULE_DIRS[@]} changed module(s):"
    for dir in "${MODULE_DIRS[@]}"; do
      echo "  - $dir"
    done
    echo ""

    local subdirs="${MODULE_DIRS[*]}"
  fi

  for dir in $subdirs; do
    # Skip over any directories that obviously don't have the necessary
    # files
    if test -f "$dir/main.tf"; then
      validate_terraform_directory "$dir"
    fi
  done
}

main
