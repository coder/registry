#!/bin/bash

# Version Bump Script
# Usage: ./version-bump.sh <bump_type> [base_ref]
#   bump_type: patch, minor, or major
#   base_ref: base reference for diff (default: origin/main)

set -euo pipefail

usage() {
  echo "Usage: $0 <bump_type> [base_ref]"
  echo "  bump_type: patch, minor, or major"
  echo "  base_ref: base reference for diff (default: origin/main)"
  echo ""
  echo "Examples:"
  echo "  $0 patch                    # Update versions with patch bump"
  echo "  $0 minor                    # Update versions with minor bump"
  echo "  $0 major                    # Update versions with major bump"
  exit 1
}

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Invalid version format: '$version'. Expected X.Y.Z format." >&2
    return 1
  fi
  return 0
}

bump_version() {
  local current_version="$1"
  local bump_type="$2"

  IFS='.' read -r major minor patch <<< "$current_version"

  if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]] || ! [[ "$patch" =~ ^[0-9]+$ ]]; then
    echo "❌ Version components must be numeric: major='$major' minor='$minor' patch='$patch'" >&2
    return 1
  fi

  case "$bump_type" in
    "patch")
      echo "$major.$minor.$((patch + 1))"
      ;;
    "minor")
      echo "$major.$((minor + 1)).0"
      ;;
    "major")
      echo "$((major + 1)).0.0"
      ;;
    *)
      echo "❌ Invalid bump type: '$bump_type'. Expected patch, minor, or major." >&2
      return 1
      ;;
  esac
}

update_readme_version() {
  local readme_path="$1"
  local namespace="$2"
  local module_name="$3"
  local new_version="$4"

  if [ ! -f "$readme_path" ]; then
    return 1
  fi

  local module_source="registry.coder.com/${namespace}/${module_name}/coder"
  if grep -q "source.*${module_source}" "$readme_path"; then
    echo "Updating version references for $namespace/$module_name in $readme_path"
    awk -v module_source="$module_source" -v new_version="$new_version" '
        /source.*=.*/ {
          if ($0 ~ module_source) {
            in_target_module = 1
          } else {
            in_target_module = 0
          }
        }
        /version.*=.*"/ {
          if (in_target_module) {
            gsub(/version[[:space:]]*=[[:space:]]*"[^"]*"/, "version = \"" new_version "\"")
            in_target_module = 0
          }
        }
        { print }
        ' "$readme_path" > "${readme_path}.tmp" && mv "${readme_path}.tmp" "$readme_path"
    return 0
  elif grep -q 'version\s*=\s*"' "$readme_path"; then
    echo "⚠️  Found version references but no module source match for $namespace/$module_name"
    return 1
  fi

  return 1
}

main() {
  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
  fi

  local bump_type="$1"
  local base_ref="${2:-origin/main}"

  case "$bump_type" in
    "patch" | "minor" | "major") ;;

    *)
      echo "❌ Invalid bump type: '$bump_type'. Expected patch, minor, or major." >&2
      exit 1
      ;;
  esac

  echo "🔍 Detecting modified modules..."

  local changed_files
  changed_files=$(git diff --name-only "${base_ref}"...HEAD)
  local modules
  modules=$(echo "$changed_files" | grep -E '^registry/[^/]+/modules/[^/]+/' | cut -d'/' -f1-4 | sort -u)

  if [ -z "$modules" ]; then
    echo "❌ No modules detected in changes"
    exit 1
  fi

  echo "Found modules:"
  echo "$modules"
  echo ""

  local bumped_modules=""
  local updated_readmes=""
  local untagged_modules=""
  local has_changes=false

  while IFS= read -r module_path; do
    if [ -z "$module_path" ]; then continue; fi

    local namespace
    namespace=$(echo "$module_path" | cut -d'/' -f2)
    local module_name
    module_name=$(echo "$module_path" | cut -d'/' -f4)

    echo "📦 Processing: $namespace/$module_name"

    local latest_tag
    latest_tag=$(git tag -l "release/${namespace}/${module_name}/v*" | sort -V | tail -1)
    local readme_path="$module_path/README.md"
    local current_version

    if [ -z "$latest_tag" ]; then
      if [ -f "$readme_path" ] && grep -q 'version\s*=\s*"' "$readme_path"; then
        local readme_version
        readme_version=$(grep 'version\s*=\s*"' "$readme_path" | head -1 | sed 's/.*version\s*=\s*"\([^"]*\)".*/\1/')
        echo "No git tag found, but README shows version: $readme_version"

        if ! validate_version "$readme_version"; then
          echo "Starting from v1.0.0 instead"
          current_version="1.0.0"
        else
          current_version="$readme_version"
          untagged_modules="$untagged_modules\n- $namespace/$module_name (README: v$readme_version)"
        fi
      else
        echo "No existing tags or version references found for $namespace/$module_name, starting from v1.0.0"
        current_version="1.0.0"
      fi
    else
      current_version=$(echo "$latest_tag" | sed 's/.*\/v//')
      echo "Found git tag: $latest_tag (v$current_version)"
    fi

    echo "Current version: $current_version"

    if ! validate_version "$current_version"; then
      exit 1
    fi

    local new_version
    new_version=$(bump_version "$current_version" "$bump_type")

    echo "New version: $new_version"

    if update_readme_version "$readme_path" "$namespace" "$module_name" "$new_version"; then
      updated_readmes="$updated_readmes\n- $namespace/$module_name"
      has_changes=true
    fi

    bumped_modules="$bumped_modules\n- $namespace/$module_name: v$current_version → v$new_version"
    echo ""

  done <<< "$modules"

  # Always run formatter to ensure consistent formatting
  echo "🔧 Running formatter to ensure consistent formatting..."
  if command -v bun >/dev/null 2>&1; then
    bun fmt >/dev/null 2>&1 || echo "⚠️  Warning: bun fmt failed, but continuing..."
  else
    echo "⚠️  Warning: bun not found, skipping formatting"
  fi
  echo ""

  echo "📋 Summary:"
  echo "Bump Type: $bump_type"
  echo ""
  echo "Modules Updated:"
  echo -e "$bumped_modules"
  echo ""

  if [ -n "$updated_readmes" ]; then
    echo "READMEs Updated:"
    echo -e "$updated_readmes"
    echo ""
  fi

  if [ -n "$untagged_modules" ]; then
    echo "⚠️  Modules Without Git Tags:"
    echo -e "$untagged_modules"
    echo "These modules were versioned based on README content. Consider creating proper release tags after merging."
    echo ""
  fi

  if [ "$has_changes" = true ]; then
    echo "✅ Version bump completed successfully!"
    echo "📝 README files have been updated with new versions."
    echo ""
    echo "Next steps:"
    echo "1. Review the changes: git diff"
    echo "2. Commit the changes: git add . && git commit -m 'chore: bump module versions ($bump_type)'"
    echo "3. Push the changes: git push"
    exit 0
  else
    echo "ℹ️  No README files were updated (no version references found matching module sources)."
    echo "Version calculations completed, but no files were modified."
    exit 0
  fi
}

main "$@"
