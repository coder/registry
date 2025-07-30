#!/bin/bash

# Tag Release Script
# Automatically detects modules that need tagging and creates release tags
# Usage: ./tag_release.sh
# Operates on the current checked-out commit

set -euo pipefail

MODULES_TO_TAG=()

usage() {
  echo "Usage: $0"
  echo ""
  echo "This script will:"
  echo "  1. Scan all modules in the registry"
  echo "  2. Check which modules need new release tags"
  echo "  3. Extract version information from README files"
  echo "  4. Generate a report for confirmation"
  echo "  5. Create and push release tags after confirmation"
  echo ""
  echo "The script operates on the current checked-out commit."
  echo "Make sure you have checked out the commit you want to tag before running."
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

extract_version_from_readme() {
  local readme_path="$1"
  local namespace="$2"
  local module_name="$3"

  [ ! -f "$readme_path" ] && return 1

  local version_line
  version_line=$(grep -E "source\s*=\s*\"registry\.coder\.com/${namespace}/${module_name}" "$readme_path" | head -1 || echo "")

  if [ -n "$version_line" ]; then
    local version
    version=$(echo "$version_line" | sed -n 's/.*version\s*=\s*"\([^"]*\)".*/\1/p')
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi

  local fallback_version
  fallback_version=$(grep -E 'version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' "$readme_path" | head -1 | sed 's/.*version\s*=\s*"\([^"]*\)".*/\1/' || echo "")

  if [ -n "$fallback_version" ]; then
    echo "$fallback_version"
    return 0
  fi

  return 1
}

check_module_needs_tagging() {
  local namespace="$1"
  local module_name="$2"
  local readme_version="$3"

  local tag_name="release/${namespace}/${module_name}/v${readme_version}"

  if git rev-parse --verify "$tag_name" > /dev/null 2>&1; then
    return 1
  else
    return 0
  fi
}

detect_modules_needing_tags() {
  MODULES_TO_TAG=()

  echo "🔍 Scanning all modules for missing release tags..."
  echo ""

  local all_modules
  all_modules=$(find registry -mindepth 3 -maxdepth 3 -type d -path "*/modules/*" | sort -u || echo "")

  [ -z "$all_modules" ] && {
    echo "❌ No modules found to check"
    return 1
  }

  local total_checked=0
  local needs_tagging=0

  while IFS= read -r module_path; do
    if [ -z "$module_path" ]; then continue; fi

    local namespace
    namespace=$(echo "$module_path" | cut -d'/' -f2)
    local module_name
    module_name=$(echo "$module_path" | cut -d'/' -f4)

    total_checked=$((total_checked + 1))

    local readme_path="$module_path/README.md"
    local readme_version

    if ! readme_version=$(extract_version_from_readme "$readme_path" "$namespace" "$module_name"); then
      echo "⚠️  $namespace/$module_name: No version found in README, skipping"
      continue
    fi

    if ! validate_version "$readme_version"; then
      echo "⚠️  $namespace/$module_name: Invalid version format '$readme_version', skipping"
      continue
    fi

    if check_module_needs_tagging "$namespace" "$module_name" "$readme_version"; then
      echo "📦 $namespace/$module_name: v$readme_version (needs tag)"
      MODULES_TO_TAG+=("$module_path:$namespace:$module_name:$readme_version")
      needs_tagging=$((needs_tagging + 1))
    else
      echo "✅ $namespace/$module_name: v$readme_version (already tagged)"
    fi

  done <<< "$all_modules"

  echo ""
  echo "📊 Summary: $needs_tagging of $total_checked modules need tagging"
  echo ""

  [ $needs_tagging -eq 0 ] && {
    echo "🎉 All modules are up to date! No tags needed."
    return 0
  }

  echo "## Tags to be created:"
  for module_info in "${MODULES_TO_TAG[@]}"; do
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"
    echo "- \`release/$namespace/$module_name/v$version\`"
  done
  echo ""

  return 0
}

create_and_push_tags() {
  [ ${#MODULES_TO_TAG[@]} -eq 0 ] && {
    echo "❌ No modules to tag found"
    return 1
  }

  local current_commit
  current_commit=$(git rev-parse HEAD)

  echo "🏷️  Creating release tags for commit: $current_commit"
  echo ""

  local created_tags=0
  local failed_tags=0

  for module_info in "${MODULES_TO_TAG[@]}"; do
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"

    local tag_name="release/$namespace/$module_name/v$version"
    local tag_message="Release $namespace/$module_name v$version"

    echo "Creating tag: $tag_name"

    if git tag -a "$tag_name" -m "$tag_message" "$current_commit"; then
      echo "✅ Created: $tag_name"
      created_tags=$((created_tags + 1))
    else
      echo "❌ Failed to create: $tag_name"
      failed_tags=$((failed_tags + 1))
    fi
  done

  echo ""
  echo "📊 Tag creation summary:"
  echo "  Created: $created_tags"
  echo "  Failed: $failed_tags"
  echo ""

  [ $created_tags -eq 0 ] && {
    echo "❌ No tags were created successfully"
    return 1
  }

  echo "🚀 Pushing tags to origin..."

  local tags_to_push=()
  for module_info in "${MODULES_TO_TAG[@]}"; do
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"
    local tag_name="release/$namespace/$module_name/v$version"

    if git rev-parse --verify "$tag_name" > /dev/null 2>&1; then
      tags_to_push+=("$tag_name")
    fi
  done

  local pushed_tags=0
  local failed_pushes=0

  if [ ${#tags_to_push[@]} -eq 0 ]; then
    echo "❌ No valid tags found to push"
  else
    if git push --atomic origin "${tags_to_push[@]}"; then
      echo "✅ Successfully pushed all ${#tags_to_push[@]} tags"
      pushed_tags=${#tags_to_push[@]}
    else
      echo "❌ Failed to push tags"
      failed_pushes=${#tags_to_push[@]}
    fi
  fi

  echo ""
  echo "📊 Push summary:"
  echo "  Pushed: $pushed_tags"
  echo "  Failed: $failed_pushes"
  echo ""

  if [ $pushed_tags -gt 0 ]; then
    echo "🎉 Successfully created and pushed $pushed_tags release tags!"
    echo ""
    echo "📝 Next steps:"
    echo "  - Tags will be automatically published to registry.coder.com"
    echo "  - Monitor the registry website for updates"
    echo "  - Check GitHub releases for any issues"
  fi

  return 0
}

main() {
  [ $# -gt 0 ] && usage

  echo "🚀 Coder Registry Tag Release Script"
  echo "Operating on commit: $(git rev-parse HEAD)"
  echo ""

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
  fi

  detect_modules_needing_tags || exit 1

  [ ${#MODULES_TO_TAG[@]} -eq 0 ] && {
    echo "✨ No modules need tagging. All done!"
    exit 0
  }

  echo ""
  echo "❓ Do you want to proceed with creating and pushing these release tags?"
  echo "   This will create git tags and push them to the remote repository."
  echo ""
  read -p "Continue? [y/N]: " -r response

  case "$response" in
    [yY] | [yY][eE][sS])
      echo ""
      create_and_push_tags
      ;;
    *)
      echo ""
      echo "🚫 Operation cancelled by user"
      exit 0
      ;;
  esac
}

main "$@"
