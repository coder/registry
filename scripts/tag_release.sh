#!/bin/bash

# Tag Release Script
# Automatically detects modules that need tagging and creates release tags
# Usage: ./tag_release.sh [OPTIONS]
# Operates on the current checked-out commit

set -euo pipefail

MODULES_TO_TAG=()
AUTO_APPROVE=false
DRY_RUN=false
VERBOSE=false
QUIET=false
OUTPUT_FORMAT="plain"
TARGET_NAMESPACE=""
TARGET_MODULE=""
SKIP_PUSH=false

JSON_OUTPUT='{
  "metadata": {},
  "summary": {},
  "modules": [],
  "warnings": [],
  "errors": []
}'

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_NO_ACTION_NEEDED=2
readonly EXIT_VALIDATION_FAILED=3

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -y, --auto-approve       Skip confirmation prompt
  -d, --dry-run           Preview without creating tags
  -v, --verbose           Detailed output
  -q, --quiet             Minimal output
  -f, --format=FORMAT     Output format: 'plain' or 'json'
  -n, --namespace=NAME    Target specific namespace
  -m, --module=NAME       Target specific module
  -s, --skip-push         Create tags but don't push
  -h, --help              Show this help

EXAMPLES:
  $0                      # Interactive mode
  $0 -y -q -f json        # CI/CD automation
  $0 -d -v                # Test with verbose output
  $0 -m code-server -d    # Target specific module
  $0 -n coder -m code-server -d  # Target module in namespace

Exit codes: 0=success, 1=error, 2=no action needed, 3=validation failed
EOF
  exit 0
}

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  case "$level" in
    "ERROR")
      if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        add_json_error "script_error" "$message"
      elif [[ "$QUIET" != "true" ]]; then
        echo "❌ $message" >&2
      fi
      ;;
    "WARN")
      if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        add_json_warning "" "$message" "warning"
      elif [[ "$QUIET" != "true" ]]; then
        echo "⚠️  $message" >&2
      fi
      ;;
    "INFO")
      if [[ "$QUIET" != "true" && "$OUTPUT_FORMAT" != "json" ]]; then
        echo "$message"
      fi
      ;;
    "SUCCESS")
      if [[ "$QUIET" != "true" && "$OUTPUT_FORMAT" != "json" ]]; then
        echo "✅ $message"
      fi
      ;;
    "DEBUG")
      if [[ "$VERBOSE" == "true" && "$OUTPUT_FORMAT" != "json" ]]; then
        echo "🔍 [$timestamp] $message" >&2
      fi
      ;;
  esac
}

add_json_error() {
  local type="$1"
  local message="$2"
  local details="${3:-}"
  local exit_code="${4:-1}"

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg type "$type" --arg msg "$message" --arg details "$details" --argjson code "$exit_code" '.errors += [{"type": $type, "message": $msg, "details": $details, "exit_code": $code}]')
}

add_json_warning() {
  local module="$1"
  local message="$2"
  local type="$3"

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg module "$module" --arg msg "$message" --arg type "$type" '.warnings += [{"module": $module, "message": $msg, "type": $type}]')
}

add_json_module() {
  local namespace="$1"
  local module_name="$2"
  local path="$3"
  local version="$4"
  local tag_name="$5"
  local status="$6"
  local already_existed="$7"

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg ns "$namespace" --arg name "$module_name" --arg path "$path" --arg version "$version" --arg tag "$tag_name" --arg status "$status" --argjson existed "$already_existed" '.modules += [{"namespace": $ns, "module_name": $name, "path": $path, "version": $version, "tag_name": $tag, "status": $status, "already_existed": $existed}]')
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -y | --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      -d | --dry-run)
        DRY_RUN=true
        shift
        ;;
      -v | --verbose)
        VERBOSE=true
        shift
        ;;
      -q | --quiet)
        QUIET=true
        shift
        ;;
      -f | --format=* | --format)
        if [[ "$1" == "-f" || "$1" == "--format" ]]; then
          if [[ -z "$2" ]]; then
            log "ERROR" "Option $1 requires a value"
            exit $EXIT_ERROR
          fi
          OUTPUT_FORMAT="$2"
          shift 2
        else
          OUTPUT_FORMAT="${1#*=}"
          shift
        fi
        if [[ "$OUTPUT_FORMAT" != "plain" && "$OUTPUT_FORMAT" != "json" ]]; then
          log "ERROR" "Invalid format '$OUTPUT_FORMAT'. Must be 'plain' or 'json'"
          exit $EXIT_ERROR
        fi
        ;;
      -n | --namespace=* | --namespace)
        if [[ "$1" == "-n" || "$1" == "--namespace" ]]; then
          if [[ -z "$2" ]]; then
            log "ERROR" "Option $1 requires a value"
            exit $EXIT_ERROR
          fi
          TARGET_NAMESPACE="$2"
          shift 2
        else
          TARGET_NAMESPACE="${1#*=}"
          shift
        fi
        ;;
      -m | --module=* | --module)
        if [[ "$1" == "-m" || "$1" == "--module" ]]; then
          if [[ -z "$2" ]]; then
            log "ERROR" "Option $1 requires a value"
            exit $EXIT_ERROR
          fi
          TARGET_MODULE="$2"
          shift 2
        else
          TARGET_MODULE="${1#*=}"
          shift
        fi
        ;;
      -s | --skip-push)
        SKIP_PUSH=true
        shift
        ;;
      -h | --help)
        usage
        ;;
      *)
        log "ERROR" "Unknown option: $1"
        echo "Use --help for usage information."
        exit $EXIT_ERROR
        ;;
    esac
  done

  if [[ "$VERBOSE" == "true" && "$QUIET" == "true" ]]; then
    echo "❌ --verbose and --quiet cannot be used together" >&2
    exit $EXIT_ERROR
  fi
}

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "DEBUG" "Invalid version format: '$version'. Expected X.Y.Z format."
    return 1
  fi
  return 0
}

extract_version_from_readme() {
  local readme_path="$1"
  local namespace="$2"
  local module_name="$3"

  log "DEBUG" "Extracting version from $readme_path for $namespace/$module_name"

  [ ! -f "$readme_path" ] && {
    log "DEBUG" "README file not found: $readme_path"
    return 1
  }

  local version_line
  version_line=$(grep -E "source[[:space:]]*=[[:space:]]*\"registry\.coder\.com/${namespace}/${module_name}" "$readme_path" | head -1 || echo "")

  if [ -n "$version_line" ]; then
    local version
    version=$(echo "$version_line" | sed -n 's/.*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$version" ]; then
      log "DEBUG" "Found version '$version' from source line: $version_line"
      echo "$version"
      return 0
    fi
  fi

  local fallback_version
  fallback_version=$(grep -E 'version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$readme_path" | head -1 | sed 's/.*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "")

  if [ -n "$fallback_version" ]; then
    log "DEBUG" "Found fallback version '$fallback_version'"
    echo "$fallback_version"
    return 0
  fi

  log "DEBUG" "No version found in $readme_path"
  return 1
}

check_module_needs_tagging() {
  local namespace="$1"
  local module_name="$2"
  local readme_version="$3"

  local tag_name="release/${namespace}/${module_name}/v${readme_version}"

  log "DEBUG" "Checking if tag exists: $tag_name"

  if git rev-parse --verify "$tag_name" > /dev/null 2>&1; then
    log "DEBUG" "Tag $tag_name already exists"
    return 1
  else
    log "DEBUG" "Tag $tag_name needs to be created"
    return 0
  fi
}

should_process_module() {
  local namespace="$1"
  local module_name="$2"

  if [[ -n "$TARGET_NAMESPACE" && "$TARGET_NAMESPACE" != "$namespace" ]]; then
    log "DEBUG" "Skipping $namespace/$module_name: namespace filter"
    return 1
  fi

  if [[ -n "$TARGET_MODULE" && "$TARGET_MODULE" != "$module_name" ]]; then
    log "DEBUG" "Skipping $namespace/$module_name: module filter"
    return 1
  fi

  return 0
}

detect_modules_needing_tags() {
  MODULES_TO_TAG=()

  log "INFO" "🔍 Scanning all modules for missing release tags..."
  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo ""
  fi

  local all_modules
  all_modules=$(find registry -mindepth 3 -maxdepth 3 -type d -path "*/modules/*" | sort -u || echo "")

  [ -z "$all_modules" ] && {
    log "ERROR" "No modules found to check"
    return $EXIT_ERROR
  }

  local total_checked=0
  local needs_tagging=0
  local already_tagged=0
  local skipped=0

  while IFS= read -r module_path; do
    if [ -z "$module_path" ]; then continue; fi

    local namespace
    namespace=$(echo "$module_path" | cut -d'/' -f2)
    local module_name
    module_name=$(echo "$module_path" | cut -d'/' -f4)

    if ! should_process_module "$namespace" "$module_name"; then
      skipped=$((skipped + 1))
      continue
    fi

    total_checked=$((total_checked + 1))

    local readme_path="$module_path/README.md"
    local readme_version

    if ! readme_version=$(extract_version_from_readme "$readme_path" "$namespace" "$module_name"); then
      log "WARN" "$namespace/$module_name: No version found in README, skipping"
      add_json_warning "$namespace/$module_name" "No version found in README, skipping" "missing_version"
      skipped=$((skipped + 1))
      continue
    fi

    if ! validate_version "$readme_version"; then
      log "WARN" "$namespace/$module_name: Invalid version format '$readme_version', skipping"
      add_json_warning "$namespace/$module_name" "Invalid version format '$readme_version', skipping" "invalid_version"
      skipped=$((skipped + 1))
      continue
    fi

    local tag_name="release/$namespace/$module_name/v$readme_version"

    if check_module_needs_tagging "$namespace" "$module_name" "$readme_version"; then
      log "INFO" "📦 $namespace/$module_name: v$readme_version (needs tag)"
      MODULES_TO_TAG+=("$module_path:$namespace:$module_name:$readme_version")
      needs_tagging=$((needs_tagging + 1))

      local status="needs_tagging"
      if [[ "$DRY_RUN" == "true" ]]; then
        status="would_be_tagged"
      fi
      add_json_module "$namespace" "$module_name" "$module_path" "$readme_version" "$tag_name" "$status" false
    else
      log "SUCCESS" "$namespace/$module_name: v$readme_version (already tagged)"
      already_tagged=$((already_tagged + 1))
      add_json_module "$namespace" "$module_name" "$module_path" "$readme_version" "$tag_name" "already_tagged" true
    fi

  done <<< "$all_modules"

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --argjson total "$total_checked" --argjson needs "$needs_tagging" \
    --argjson tagged "$already_tagged" --argjson skip "$skipped" \
    '.summary.total_scanned = $total | .summary.needs_tagging = $needs | .summary.already_tagged = $tagged | .summary.skipped = $skip')

  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo ""
    log "INFO" "📊 Summary: $needs_tagging of $total_checked modules need tagging"
    echo ""
  fi

  [ $needs_tagging -eq 0 ] && {
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
      log "SUCCESS" "🎉 All modules are up to date! No tags needed."
    fi
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "no_action_needed"')
    return $EXIT_NO_ACTION_NEEDED
  }

  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo "## Tags to be created:"
    for module_info in "${MODULES_TO_TAG[@]}"; do
      IFS=':' read -r module_path namespace module_name version <<< "$module_info"
      echo "- \`release/$namespace/$module_name/v$version\`"
    done
    echo ""
  fi

  return $EXIT_SUCCESS
}

pre_flight_checks() {
  log "DEBUG" "Running pre-flight checks..."

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "ERROR" "Not in a git repository"
    return $EXIT_ERROR
  fi

  if ! git remote get-url origin > /dev/null 2>&1; then
    log "ERROR" "No 'origin' remote found"
    return $EXIT_ERROR
  fi

  if [[ "$SKIP_PUSH" != "true" && "$DRY_RUN" != "true" ]]; then
    log "DEBUG" "Testing remote connectivity..."
    if ! git ls-remote --exit-code origin > /dev/null 2>&1; then
      log "ERROR" "Cannot connect to remote repository"
      return $EXIT_ERROR
    fi
  fi

  if ! git rev-parse HEAD > /dev/null 2>&1; then
    log "ERROR" "Cannot determine current commit"
    return $EXIT_ERROR
  fi

  log "DEBUG" "Pre-flight checks passed"
  return $EXIT_SUCCESS
}

create_and_push_tags() {
  [ ${#MODULES_TO_TAG[@]} -eq 0 ] && {
    log "ERROR" "No modules to tag found"
    return $EXIT_ERROR
  }

  local current_commit
  current_commit=$(git rev-parse HEAD)

  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "🏷️  [DRY RUN] Would create release tags for commit: $current_commit"
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "dry_run" | .summary.tags_created = 0 | .summary.tags_pushed = 0')
    return $EXIT_SUCCESS
  fi

  log "INFO" "🏷️  Creating release tags for commit: $current_commit"
  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo ""
  fi

  local created_tags=0
  local failed_tags=0
  local created_tag_names=()

  for module_info in "${MODULES_TO_TAG[@]}"; do
    IFS=':' read -r module_path namespace module_name version <<< "$module_info"

    local tag_name="release/$namespace/$module_name/v$version"
    local tag_message="Release $namespace/$module_name v$version"

    log "DEBUG" "Creating tag: $tag_name"
    log "INFO" "Creating tag: $tag_name"

    if git tag -a "$tag_name" -m "$tag_message" "$current_commit" 2> /dev/null; then
      log "SUCCESS" "Created: $tag_name"
      created_tags=$((created_tags + 1))
      created_tag_names+=("$tag_name")

      JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg tag "$tag_name" \
        '(.modules[] | select(.tag_name == $tag) | .status) = "tag_created"')
    else
      log "ERROR" "Failed to create: $tag_name"
      add_json_error "tag_creation_failed" "Failed to create tag: $tag_name" "git tag -a $tag_name -m '$tag_message' $current_commit"
      failed_tags=$((failed_tags + 1))

      JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg tag "$tag_name" \
        '(.modules[] | select(.tag_name == $tag) | .status) = "tag_creation_failed"')
    fi
  done

  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo ""
    log "INFO" "📊 Tag creation summary:"
    log "INFO" "  Created: $created_tags"
    log "INFO" "  Failed: $failed_tags"
    echo ""
  fi

  [ $created_tags -eq 0 ] && {
    log "ERROR" "No tags were created successfully"
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "failed" | .summary.tags_created = 0 | .summary.tags_pushed = 0')
    return $EXIT_ERROR
  }

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --argjson created "$created_tags" '.summary.tags_created = $created')

  if [[ "$SKIP_PUSH" == "true" ]]; then
    log "INFO" "🚫 Skipping push (--skip-push specified)"
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "tags_created_not_pushed" | .summary.tags_pushed = 0')
    for tag_name in "${created_tag_names[@]}"; do
      JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg tag "$tag_name" \
        '(.modules[] | select(.tag_name == $tag) | .status) = "tag_created_not_pushed"')
    done
    return $EXIT_SUCCESS
  fi

  log "INFO" "🚀 Pushing tags to origin..."

  local tags_to_push=()
  for tag_name in "${created_tag_names[@]}"; do
    if git rev-parse --verify "$tag_name" > /dev/null 2>&1; then
      tags_to_push+=("$tag_name")
    fi
  done

  local pushed_tags=0
  local failed_pushes=0

  if [ ${#tags_to_push[@]} -eq 0 ]; then
    log "ERROR" "No valid tags found to push"
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "failed" | .summary.tags_pushed = 0')
  else
    if git push --atomic origin "${tags_to_push[@]}" 2> /dev/null; then
      log "SUCCESS" "Successfully pushed all ${#tags_to_push[@]} tags"
      pushed_tags=${#tags_to_push[@]}

      for tag_name in "${tags_to_push[@]}"; do
        JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg tag "$tag_name" \
          '(.modules[] | select(.tag_name == $tag) | .status) = "tagged_and_pushed"')
      done
    else
      log "ERROR" "Failed to push tags"
      add_json_error "push_failed" "Failed to push tags to remote" "git push --atomic origin ${tags_to_push[*]}"
      failed_pushes=${#tags_to_push[@]}

      for tag_name in "${tags_to_push[@]}"; do
        JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg tag "$tag_name" \
          '(.modules[] | select(.tag_name == $tag) | .status) = "tag_created_push_failed"')
      done
    fi
  fi

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --argjson pushed "$pushed_tags" '.summary.tags_pushed = $pushed')

  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo ""
    log "INFO" "📊 Push summary:"
    log "INFO" "  Pushed: $pushed_tags"
    log "INFO" "  Failed: $failed_pushes"
    echo ""
  fi

  if [ $pushed_tags -gt 0 ]; then
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
      log "SUCCESS" "🎉 Successfully created and pushed $pushed_tags release tags!"
      echo ""
      log "INFO" "📝 Next steps:"
      log "INFO" "  - Tags will be automatically published to registry.coder.com"
      log "INFO" "  - Monitor the registry website for updates"
      log "INFO" "  - Check GitHub releases for any issues"
    fi
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "success"')
    return $EXIT_SUCCESS
  else
    JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "failed"')
    return $EXIT_ERROR
  fi
}

finalize_json_output() {
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local current_commit
  current_commit=$(git rev-parse HEAD 2> /dev/null || echo "unknown")
  local command_line="$0 $*"

  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg ts "$timestamp" --arg commit "$current_commit" \
    --arg cmd "$command_line" \
    '.metadata.timestamp = $ts | .metadata.commit = $commit | .metadata.command = $cmd')

  echo "$JSON_OUTPUT"
}

main() {
  parse_arguments "$@"

  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    if ! command -v jq > /dev/null 2>&1; then
      echo '{"error": "jq is required for JSON output format but not found"}' >&2
      exit $EXIT_ERROR
    fi
  fi

  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    log "INFO" "🚀 Coder Registry Tag Release Script"
    log "INFO" "Operating on commit: $(git rev-parse HEAD 2> /dev/null || echo 'unknown')"
    echo ""
  fi

  if ! pre_flight_checks; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "preflight_failed"')
      finalize_json_output "$@"
    fi
    exit $EXIT_ERROR
  fi

  local detect_exit_code
  detect_modules_needing_tags
  detect_exit_code=$?

  case $detect_exit_code in
    $EXIT_NO_ACTION_NEEDED)
      if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        finalize_json_output "$@"
      else
        log "SUCCESS" "✨ No modules need tagging. All done!"
      fi
      exit $EXIT_SUCCESS
      ;;
    $EXIT_ERROR)
      if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "scan_failed"')
        finalize_json_output "$@"
      fi
      exit $EXIT_ERROR
      ;;
  esac

  if [[ "$AUTO_APPROVE" != "true" && "$OUTPUT_FORMAT" != "json" && "$DRY_RUN" != "true" ]]; then
    echo ""
    log "INFO" "❓ Do you want to proceed with creating and pushing these release tags?"
    log "INFO" "   This will create git tags and push them to the remote repository."
    echo ""
    read -p "Continue? [y/N]: " -r response

    case "$response" in
      [yY] | [yY][eE][sS])
        echo ""
        ;;
      *)
        echo ""
        log "INFO" "🚫 Operation cancelled by user"
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
          JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq '.summary.operation_status = "cancelled_by_user"')
          finalize_json_output "$@"
        fi
        exit $EXIT_SUCCESS
        ;;
    esac
  fi

  local create_exit_code
  create_and_push_tags
  create_exit_code=$?

  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    finalize_json_output "$@"
  fi

  exit $create_exit_code
}

main "$@"
