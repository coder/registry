#!/bin/bash

set -euo pipefail

# Auto-detect which Terraform modules to validate based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
# Validates all modules if shared infrastructure changes, or skips if no changes detected
#
# This script only validates changed modules. Documentation and template changes are ignored.

# Validates that Terraform variable names use underscores (snake_case) instead
# of hyphens. Hyphens are technically valid but deprecated and non-idiomatic.
# See: https://developer.hashicorp.com/terraform/language/values/variables
validate_variable_names() {
  local dir="$1"
  local found_issues=0

  while IFS= read -r tf_file; do
    while IFS= read -r match; do
      local line_num
      line_num=$(echo "$match" | cut -d: -f1)
      local line_content
      line_content=$(echo "$match" | cut -d: -f2-)
      local var_name
      var_name=$(echo "$line_content" | sed -n 's/.*variable "\([^"]*\)".*/\1/p')

      if [[ -n "$var_name" ]]; then
        echo "  ERROR: $tf_file:$line_num"
        echo "    Variable \"$var_name\" contains a hyphen."
        echo "    Rename to \"${var_name//-/_}\" (use underscores instead of hyphens)."
        found_issues=$((found_issues + 1))
      fi
    done < <(grep -n 'variable "[^"]*-[^"]*"' "$tf_file" 2> /dev/null || true)
  done < <(find "$dir" -name '*.tf' -type f | sort)

  return "$found_issues"
}

validate_terraform_directory() {
  local dir="$1"
  echo "Running \`terraform validate\` in $dir"
  pushd "$dir" > /dev/null
  terraform init -upgrade
  terraform validate
  popd > /dev/null
}

main() {
  echo "==> Detecting changed files..."

  if [[ -n "${ALL_CHANGED_FILES:-}" ]]; then
    echo "Changed files in PR:"
    echo "$ALL_CHANGED_FILES" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""
  fi

  local script_dir
  script_dir=$(dirname "$(readlink -f "$0")")
  local registry_dir
  registry_dir=$(readlink -f "$script_dir/../registry")

  if [[ "${SHARED_CHANGED:-false}" == "true" ]]; then
    echo "==> Shared infrastructure changed"
    echo "==> Validating all modules for safety"
    local subdirs
    subdirs=$(find "$registry_dir" -mindepth 3 -maxdepth 3 -path "*/modules/*" -type d | sort)
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
        local namespace
        namespace="${BASH_REMATCH[1]}"
        local module
        module="${BASH_REMATCH[2]}"
        local module_dir
        module_dir="registry/${namespace}/modules/${module}"

        if [[ -d "$module_dir" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " $module_dir " ]]; then
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

  status=0
  for dir in $subdirs; do
    # Skip over any directories that obviously don't have the necessary
    # files
    if test -f "$dir/main.tf"; then
      if ! validate_terraform_directory "$dir"; then
        status=1
      fi
    fi
  done

  echo ""
  echo "==> Validating Terraform variable names use snake_case..."
  for dir in $subdirs; do
    if test -f "$dir/main.tf"; then
      if ! validate_variable_names "$dir"; then
        status=1
      fi
    fi
  done

  exit $status
}

main
