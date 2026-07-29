#!/bin/bash

set -euo pipefail

# Auto-detect which Terraform modules and templates to validate based on changed
# files from paths-filter.
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
#   TEMPLATE_CHANGED_FILES - only files in registry/**/templates/** (for processing)
# Validates all modules and templates if shared infrastructure changes, or skips
# if no changes detected.
#
# This script validates changed modules and templates. Documentation changes are ignored.

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
  done < <(find "$dir" -path '*/.terraform/*' -prune -o -name '*.tf' -type f -print | sort)

  return "$found_issues"
}

validate_terraform_directory() {
  local dir="$1"
  local rc=0
  echo "Running \`terraform validate\` in $dir"
  pushd "$dir" > /dev/null

  # `terraform validate` requires modules to be installed first. If
  # `terraform init` fails (for example a bad module source), skip validate
  # so we surface the real init error instead of misleading
  # "Module not installed" errors.
  if ! terraform init -upgrade; then
    echo "  ERROR: \`terraform init\` failed in $dir" >&2
    popd > /dev/null
    return 1
  fi

  terraform validate || rc=1

  popd > /dev/null
  return "$rc"
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
    echo "==> Validating all modules and templates for safety"
    local subdirs
    subdirs=$(find "$registry_dir" -mindepth 3 -maxdepth 3 \( -path "*/modules/*" -o -path "*/templates/*" \) -type d | sort)
  elif [[ -z "${MODULE_CHANGED_FILES:-}" ]] && [[ -z "${TEMPLATE_CHANGED_FILES:-}" ]]; then
    echo "✓ No module or template files changed, skipping validation"
    exit 0
  else
    CHANGED_FILES=$(echo "${MODULE_CHANGED_FILES:-} ${TEMPLATE_CHANGED_FILES:-}" | tr ' ' '\n')

    TF_DIRS=()
    while IFS= read -r file; do
      if [[ "$file" =~ \.(md|png|jpg|jpeg|svg)$ ]]; then
        continue
      fi

      if [[ "$file" =~ ^registry/([^/]+)/(modules|templates)/([^/]+)/ ]]; then
        local namespace
        namespace="${BASH_REMATCH[1]}"
        local kind
        kind="${BASH_REMATCH[2]}"
        local name
        name="${BASH_REMATCH[3]}"
        local tf_dir
        tf_dir="registry/${namespace}/${kind}/${name}"

        if [[ -d "$tf_dir" ]] && [[ ! " ${TF_DIRS[*]} " =~ " $tf_dir " ]]; then
          TF_DIRS+=("$tf_dir")
        fi
      fi
    done <<< "$CHANGED_FILES"

    if [[ ${#TF_DIRS[@]} -eq 0 ]]; then
      echo "✓ No modules or templates to validate"
      echo "  (documentation, namespace files, or directories without changes)"
      exit 0
    fi

    echo "==> Validating ${#TF_DIRS[@]} changed module(s)/template(s):"
    for dir in "${TF_DIRS[@]}"; do
      echo "  - $dir"
    done
    echo ""

    local subdirs="${TF_DIRS[*]}"
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
