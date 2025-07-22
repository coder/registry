#!/bin/bash

# Tag Release Script
# Automatically detects modules that need tagging and creates release tags
# Usage: ./tag_release.sh
# Operates on the current checked-out commit

set -euo pipefail

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
  
  if [ ! -f "$readme_path" ]; then
    echo "❌ README not found: $readme_path" >&2
    return 1
  fi
  
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
  
  if git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
    return 1
  else
    return 0
  fi
}

detect_modules_needing_tags() {
  local modules_to_tag=()
  
  echo "🔍 Scanning all modules for missing release tags..."
  echo ""
  

  local all_modules
  all_modules=$(find registry -type d -path "*/modules/*" -mindepth 3 -maxdepth 3 | sort -u || echo "")
  
  if [ -z "$all_modules" ]; then
    echo "❌ No modules found to check"
    return 1
  fi
  
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
      modules_to_tag+=("$module_path:$namespace:$module_name:$readme_version")
      needs_tagging=$((needs_tagging + 1))
    else
      echo "✅ $namespace/$module_name: v$readme_version (already tagged)"
    fi
    
  done <<< "$all_modules"
  
  echo ""
  echo "📊 Summary: $needs_tagging of $total_checked modules need tagging"
  echo ""
  
  if [ $needs_tagging -eq 0 ]; then
    echo "🎉 All modules are up to date! No tags needed."
    return 0
  fi
  

  echo "## Tags to be created:"
  for module_info in "${modules_to_tag[@]}"; do
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"
    echo "- \`release/$namespace/$module_name/v$version\`"
  done
  echo ""
  

  printf '%s\n' "${modules_to_tag[@]}" > /tmp/modules_to_tag.txt
  
  return 0
}

create_and_push_tags() {
  if [ ! -f /tmp/modules_to_tag.txt ]; then
    echo "❌ No modules to tag found"
    return 1
  fi
  
  local current_commit
  current_commit=$(git rev-parse HEAD)
  
  echo "🏷️  Creating release tags for commit: $current_commit"
  echo ""
  
  local created_tags=0
  local failed_tags=0
  
  while IFS= read -r module_info; do
    if [ -z "$module_info" ]; then continue; fi
    
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
    
  done < /tmp/modules_to_tag.txt
  
  echo ""
  echo "📊 Tag creation summary:"
  echo "  Created: $created_tags"
  echo "  Failed: $failed_tags"
  echo ""
  
  if [ $created_tags -eq 0 ]; then
    echo "❌ No tags were created successfully"
    return 1
  fi
  
  echo "🚀 Pushing tags to origin..."
  
  local pushed_tags=0
  local failed_pushes=0
  
  while IFS= read -r module_info; do
    if [ -z "$module_info" ]; then continue; fi
    
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"
    
    local tag_name="release/$namespace/$module_name/v$version"
    
    if git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
      echo "Pushing: $tag_name"
      if git push origin "$tag_name"; then
        echo "✅ Pushed: $tag_name"
        pushed_tags=$((pushed_tags + 1))
      else
        echo "❌ Failed to push: $tag_name"
        failed_pushes=$((failed_pushes + 1))
      fi
    fi
    
  done < /tmp/modules_to_tag.txt
  
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
  

  rm -f /tmp/modules_to_tag.txt
  
  return 0
}

main() {
  if [ $# -gt 0 ]; then
    usage
  fi
  
  echo "🚀 Coder Registry Tag Release Script"
  echo "Operating on commit: $(git rev-parse HEAD)"
  echo ""
  

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
  fi
  

  if ! detect_modules_needing_tags; then
    exit 1
  fi
  

  if [ ! -f /tmp/modules_to_tag.txt ] || [ ! -s /tmp/modules_to_tag.txt ]; then
    echo "✨ No modules need tagging. All done!"
    exit 0
  fi
  

  echo ""
  echo "❓ Do you want to proceed with creating and pushing these release tags?"
  echo "   This will create git tags and push them to the remote repository."
  echo ""
  read -p "Continue? [y/N]: " -r response
  
  case "$response" in
    [yY]|[yY][eE][sS])
      echo ""
      create_and_push_tags
      ;;
    *)
      echo ""
      echo "🚫 Operation cancelled by user"
      rm -f /tmp/modules_to_tag.txt
      exit 0
      ;;
  esac
}

main "$@"
