#!/usr/bin/env bash

set -euo pipefail

# Variables from Terraform template
EXTENSIONS="${EXTENSIONS}"
EXTENSIONS_URLS="${EXTENSIONS_URLS}"
EXTENSIONS_DIR="${EXTENSIONS_DIR}"
IDE_TYPE="${IDE_TYPE}"

# Color constants
BOLD='\033[0;1m'
CODE='\033[36;40;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

# Check if extension is already installed
is_extension_installed() {
  local target_dir="$1"
  local extension_id="$2"
  local extension_dir="$target_dir/$extension_id"

  if [ -d "$extension_dir" ] && [ -f "$extension_dir/package.json" ]; then
    if grep -q '"name"' "$extension_dir/package.json" 2> /dev/null; then
      if grep -q '"publisher"' "$extension_dir/package.json" 2> /dev/null; then
        return 0
      fi
    fi
  fi
  return 1
}

# Generate marketplace URL for extension
generate_extension_url() {
  local extension_id="$1"

  if [[ -z "$extension_id" ]]; then
    return 1
  fi

  # Extract publisher and extension name (simple approach)
  local publisher=$(echo "$extension_id" | cut -d'.' -f1)
  local name=$(echo "$extension_id" | cut -d'.' -f2-)

  if [[ -z "$publisher" ]] || [[ -z "$name" ]]; then
    printf "$${RED}❌ Invalid extension ID format: $extension_id$${RESET}\n" >&2
    return 1
  fi

  # Generate URL based on IDE type
  case "${IDE_TYPE}" in
    "vscode" | "vscode-insiders")
      # Microsoft IDEs: Use Visual Studio Marketplace
      printf "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/%s/vsextensions/%s/latest/vspackage" "$publisher" "$name"
      ;;
    "vscodium" | "cursor" | "windsurf" | "kiro")
      # Non-Microsoft IDEs: Use Open VSX Registry
      printf "https://open-vsx.org/api/%s/%s/latest/file/%s.%s-latest.vsix" "$publisher" "$name" "$publisher" "$name"
      ;;
    *)
      # Default: Use Open VSX Registry for unknown IDEs
      printf "https://open-vsx.org/api/%s/%s/latest/file/%s.%s-latest.vsix" "$publisher" "$name" "$publisher" "$name"
      ;;
  esac
}

# Download and install extension
download_and_install_extension() {
  local target_dir="$1"
  local extension_id="$2"
  local url="$3"

  # Check if already installed (idempotency)
  if is_extension_installed "$target_dir" "$extension_id"; then
    printf "$${GREEN}✓ Extension $${CODE}$extension_id$${RESET}$${GREEN} already installed$${RESET}\n"
    return 0
  fi

  printf "$${BOLD}📦 Installing extension $${CODE}$extension_id$${RESET}...\n"

  # Create temp directory
  local temp_dir=$(mktemp -d)
  local download_file="$temp_dir/$extension_id.vsix"

  # Download with timeout
  if timeout 30 curl -fsSL "$url" -o "$download_file" 2> /dev/null; then
    # Verify the download is a valid file
    if file "$download_file" 2> /dev/null | grep -q "Zip archive"; then
      # Create target directory
      mkdir -p "$target_dir"
      local extract_dir="$target_dir/$extension_id"

      # Remove existing incomplete installation
      if [ -d "$extract_dir" ]; then
        rm -rf "$extract_dir"
      fi

      mkdir -p "$extract_dir"

      # Extract extension
      if unzip -q "$download_file" -d "$extract_dir" 2> /dev/null; then
        if [ -f "$extract_dir/package.json" ]; then
          printf "$${GREEN}✅ Successfully installed $${CODE}$extension_id$${RESET}\n"
          rm -rf "$temp_dir"
          return 0
        else
          printf "$${RED}❌ Invalid extension package$${RESET}\n"
          rm -rf "$extract_dir"
          rm -rf "$temp_dir"
          return 1
        fi
      else
        printf "$${RED}❌ Failed to extract extension$${RESET}\n"
        rm -rf "$extract_dir"
        rm -rf "$temp_dir"
        return 1
      fi
    else
      printf "$${RED}❌ Invalid file format$${RESET}\n"
      rm -rf "$temp_dir"
      return 1
    fi
  else
    printf "$${RED}❌ Download failed$${RESET}\n"
    rm -rf "$temp_dir"
    return 1
  fi
}

# Install extension from URL
install_extension_from_url() {
  local url="$1"
  local target_dir="$2"

  local extension_name=$(basename "$url" | sed 's/\.vsix$$//')
  local extension_id="$extension_name"

  printf "$${BOLD}📦 Installing extension from URL: $${CODE}$extension_name$${RESET}...\n"

  if [[ -d "$target_dir/$extension_id" ]] && [[ -f "$target_dir/$extension_id/package.json" ]]; then
    printf "$${GREEN}✓ Extension $${CODE}$extension_id$${RESET}$${GREEN} already installed$${RESET}\n"
    return 0
  fi

  # Create temp directory
  local temp_dir=$(mktemp -d)
  local download_file="$temp_dir/$extension_id.vsix"

  if timeout 30 curl -fsSL "$url" -o "$download_file" 2> /dev/null; then
    # Create target directory
    mkdir -p "$target_dir"
    local extract_dir="$target_dir/$extension_id"

    # Remove existing incomplete installation
    if [ -d "$extract_dir" ]; then
      rm -rf "$extract_dir"
    fi

    mkdir -p "$extract_dir"

    if unzip -q "$download_file" -d "$extract_dir" 2> /dev/null; then
      if [ -f "$extract_dir/package.json" ]; then
        printf "$${GREEN}✅ Successfully installed $${CODE}$extension_id$${RESET}\n"
        rm -rf "$temp_dir"
        return 0
      else
        printf "$${RED}❌ Invalid extension package$${RESET}\n"
        rm -rf "$extract_dir"
        rm -rf "$temp_dir"
        return 1
      fi
    else
      printf "$${RED}❌ Failed to extract extension$${RESET}\n"
      rm -rf "$extract_dir"
      rm -rf "$temp_dir"
      return 1
    fi
  else
    printf "$${RED}❌ Failed to download extension from URL$${RESET}\n"
    rm -rf "$temp_dir"
    return 1
  fi
}

# Install extensions from URLs
install_extensions_from_urls() {
  local urls="$1"
  local target_dir="$2"

  if [[ -z "$urls" ]]; then
    return 0
  fi

  printf "$${BOLD}🔗 Installing extensions from URLs...$${RESET}\n"

  # Simple approach: replace commas with newlines and process each URL
  echo "$urls" | tr ',' '\n' | while read -r url; do
    # Trim whitespace
    url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$url" ]; then
      install_extension_from_url "$url" "$target_dir"
    fi
  done
}

# Install extensions from extension IDs
install_extensions_from_ids() {
  local extensions="$1"
  local target_dir="$2"

  if [[ -z "$extensions" ]]; then
    return 0
  fi

  printf "$${BOLD}🧩 Installing extensions from extension IDs...$${RESET}\n"

  # Simple approach: replace commas with newlines and process each extension
  echo "$extensions" | tr ',' '\n' | while read -r extension_id; do
    # Trim whitespace
    extension_id=$(echo "$extension_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$extension_id" ]; then
      local extension_url
      extension_url=$(generate_extension_url "$extension_id")
      if [ -n "$extension_url" ]; then
        download_and_install_extension "$target_dir" "$extension_id" "$extension_url"
      else
        printf "$${RED}❌ Invalid extension ID: $extension_id$${RESET}\n"
      fi
    fi
  done
}

# Main execution
main() {
  printf "$${BOLD}🚀 Starting extension installation for $${CODE}${IDE_TYPE}$${RESET} IDE...\n"

  # Check dependencies
  for cmd in curl unzip timeout; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      printf "$${RED}❌ Missing required command: $cmd$${RESET}\n"
      return 1
    fi
  done

  # Expand tilde in extensions directory path
  local extensions_dir="${EXTENSIONS_DIR}"
  if [ "$${extensions_dir#\~}" != "$extensions_dir" ]; then
    extensions_dir="$HOME/$${extensions_dir#\~/}"
  fi

  printf "$${BOLD}📁 Using extensions directory: $${CODE}$extensions_dir$${RESET}\n"

  # Create extensions directory
  mkdir -p "$extensions_dir"
  if [[ ! -w "$extensions_dir" ]]; then
    printf "$${RED}❌ Extensions directory is not writable: $extensions_dir$${RESET}\n"
    return 1
  fi

  # Install extensions from URLs (airgapped scenario)
  if [ -n "${EXTENSIONS_URLS}" ]; then
    install_extensions_from_urls "${EXTENSIONS_URLS}" "$extensions_dir"
  fi

  # Install extensions from extension IDs (normal scenario)
  if [[ -n "${EXTENSIONS}" ]]; then
    install_extensions_from_ids "${EXTENSIONS}" "$extensions_dir"
  fi

  printf "$${BOLD}$${GREEN}✨ Extension installation completed for $${CODE}${IDE_TYPE}$${RESET}$${BOLD}$${GREEN}!$${RESET}\n"
}

# Script execution entry point
if [[ -n "${EXTENSIONS}" ]] || [[ -n "${EXTENSIONS_URLS}" ]]; then
  main
else
  printf "$${BOLD}ℹ️  No extensions to install for $${CODE}${IDE_TYPE}$${RESET}\n"
fi
