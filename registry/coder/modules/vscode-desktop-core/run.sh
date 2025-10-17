#!/usr/bin/env bash

# shellcheck disable=SC2269  # Terraform template variables
# shellcheck disable=SC2034  # Color variables used in Terraform templates
# shellcheck disable=SC2059  # printf format strings with Terraform variables

set -euo pipefail

EXTENSIONS="${EXTENSIONS}"
EXTENSIONS_URLS="${EXTENSIONS_URLS}"
EXTENSIONS_DIR="${EXTENSIONS_DIR}"
IDE_TYPE="${IDE_TYPE}"
BOLD='\033[0;1m'
CODE='\033[36;40;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

is_extension_installed() {
  local target_dir="$1"
  local extension_id="$2"
  local extension_dir="$target_dir/$extension_id"

  local package_json=""
  if [ -f "$extension_dir/package.json" ]; then
    package_json="$extension_dir/package.json"
  elif [ -f "$extension_dir/extension/package.json" ]; then
    package_json="$extension_dir/extension/package.json"
  fi

  if [ -d "$extension_dir" ] && [ -n "$package_json" ]; then
    if grep -q '"name"' "$package_json" 2> /dev/null; then
      if grep -q '"publisher"' "$package_json" 2> /dev/null; then
        return 0
      fi
    fi
  fi
  return 1
}

generate_extension_url() {
  local extension_id="$1"

  if [[ -z "$extension_id" ]]; then
    return 1
  fi

  local publisher
  publisher=$(echo "$extension_id" | cut -d'.' -f1)
  local name
  name=$(echo "$extension_id" | cut -d'.' -f2-)

  if [[ -z "$publisher" ]] || [[ -z "$name" ]]; then
    printf "$${RED}❌ Invalid extension ID format: $extension_id$${RESET}\n" >&2
    return 1
  fi

  case "${IDE_TYPE}" in
    "vscode" | "vscode-insiders")
      printf "https://marketplace.visualstudio.com/_apis/public/gallery/vscode/%s/%s/latest" "$publisher" "$name"
      ;;
    "vscodium" | "cursor" | "windsurf" | "kiro")
      printf "https://open-vsx.org/api/%s/%s/latest" "$publisher" "$name"
      ;;
    *)
      printf "https://open-vsx.org/api/%s/%s/latest" "$publisher" "$name"
      ;;
  esac
}

download_and_install_extension() {
  local target_dir="$1"
  local extension_id="$2"
  local metadata_url="$3"
  local temp_dir="$4"
  local log_file="$5"

  if is_extension_installed "$target_dir" "$extension_id"; then
    printf "$${GREEN}✓ Extension $${CODE}$extension_id$${RESET}$${GREEN} already installed$${RESET}\n"
    return 0
  fi

  printf "$${BOLD}📦 Installing extension $${CODE}$extension_id$${RESET}...\n"
  echo "$(date): Starting installation of $extension_id" >> "$log_file"

  local extension_temp_dir
  extension_temp_dir="$temp_dir/$extension_id-$(date +%s)"
  local download_file="$temp_dir/$extension_id.vsix"

  echo "$(date): Fetching metadata from $metadata_url" >> "$log_file"
  local metadata_response
  if metadata_response=$(timeout 30 curl -fsSL "$metadata_url" 2>&1); then
    local download_url
    if [[ "${IDE_TYPE}" == "vscode" || "${IDE_TYPE}" == "vscode-insiders" ]]; then
      download_url=$(echo "$metadata_response" | jq -r '.versions[0].files[] | select(.assetType == "Microsoft.VisualStudio.Services.VSIXPackage") | .source' 2> /dev/null)
    else
      download_url=$(echo "$metadata_response" | jq -r '.files.download // .downloads.universal // empty' 2> /dev/null)
    fi

    if [[ -n "$download_url" && "$download_url" != "null" ]]; then
      echo "$(date): Extracted download URL: $download_url" >> "$log_file"
      echo "$(date): Downloading extension to $download_file" >> "$log_file"
      if timeout 30 curl -fsSL "$download_url" -o "$download_file" 2>&1; then
        echo "$(date): File size: $(stat -c%s "$download_file") bytes" >> "$log_file"
        echo "$(date): Validating ZIP file..." >> "$log_file"
        if unzip -t "$download_file" > /dev/null 2>&1; then
          mkdir -p "$target_dir"
          local extract_dir="$target_dir/$extension_id"

          if [ -d "$extract_dir" ]; then
            rm -rf "$extract_dir"
          fi

          mkdir -p "$extract_dir"

          echo "$(date): Extracting to $extract_dir" >> "$log_file"
          if unzip -q "$download_file" -d "$extract_dir" 2> /dev/null; then
            if [ -f "$extract_dir/package.json" ] || [ -f "$extract_dir/extension/package.json" ]; then
              printf "$${GREEN}✅ Successfully installed $${CODE}$extension_id$${RESET}\n"
              echo "$(date): Successfully installed $extension_id" >> "$log_file"
              rm -rf "$extension_temp_dir"
              return 0
            else
              printf "$${RED}❌ Invalid extension package$${RESET}\n"
              echo "$(date): Invalid extension package for $extension_id - package.json not found" >> "$log_file"
              echo "$(date): Directory contents: $(ls -la "$extract_dir")" >> "$log_file"
              rm -rf "$extract_dir"
              rm -rf "$extension_temp_dir"
              return 1
            fi
          else
            printf "$${RED}❌ Failed to extract extension$${RESET}\n"
            echo "$(date): Failed to extract $extension_id" >> "$log_file"
            rm -rf "$extract_dir"
            rm -rf "$extension_temp_dir"
            return 1
          fi
        else
          printf "$${RED}❌ Invalid file format$${RESET}\n"
          {
            echo "$(date): ZIP validation failed for $extension_id"
            echo "$(date): File size: $(stat -c%s "$download_file") bytes"
            echo "$(date): First 100 bytes: $(head -c 100 "$download_file" | hexdump -C | head -3)"
          } >> "$log_file"
          rm -rf "$extension_temp_dir"
          return 1
        fi
      else
        printf "$${RED}❌ Download failed$${RESET}\n"
        echo "$(date): Download failed for $extension_id from $download_url" >> "$log_file"
        rm -rf "$extension_temp_dir"
        return 1
      fi
    else
      printf "$${RED}❌ Could not extract download URL from metadata$${RESET}\n"
      echo "$(date): Could not extract download URL for $extension_id" >> "$log_file"
      rm -rf "$extension_temp_dir"
      return 1
    fi
  else
    printf "$${RED}❌ Failed to fetch extension metadata$${RESET}\n"
    echo "$(date): Failed to fetch metadata for $extension_id from $metadata_url" >> "$log_file"
    rm -rf "$extension_temp_dir"
    return 1
  fi
}

install_extension_from_url() {
  local url="$1"
  local target_dir="$2"
  local temp_dir="$3"
  local log_file="$4"

  local extension_name
  extension_name=$(basename "$url" | sed 's/\.vsix$$//')
  local extension_id="$extension_name"

  printf "$${BOLD}📦 Installing extension from URL: $${CODE}$extension_name$${RESET}...\n"
  echo "$(date): Starting installation of $extension_id from URL: $url" >> "$log_file"

  if [[ -d "$target_dir/$extension_id" ]] && [[ -f "$target_dir/$extension_id/package.json" ]]; then
    printf "$${GREEN}✓ Extension $${CODE}$extension_id$${RESET}$${GREEN} already installed$${RESET}\n"
    return 0
  fi

  local extension_temp_dir
  extension_temp_dir="$temp_dir/$extension_id-$(date +%s)"
  local download_file="$temp_dir/$extension_id.vsix"

  echo "$(date): Downloading extension to $download_file" >> "$log_file"
  if timeout 30 curl -fsSL "$url" -o "$download_file" 2>&1; then
    echo "$(date): File size: $(stat -c%s "$download_file") bytes" >> "$log_file"
    mkdir -p "$target_dir"
    local extract_dir="$target_dir/$extension_id"

    if [ -d "$extract_dir" ]; then
      rm -rf "$extract_dir"
    fi

    mkdir -p "$extract_dir"

    echo "$(date): Extracting to $extract_dir" >> "$log_file"
    if unzip -q "$download_file" -d "$extract_dir" 2> /dev/null; then
      if [ -f "$extract_dir/package.json" ] || [ -f "$extract_dir/extension/package.json" ]; then
        printf "$${GREEN}✅ Successfully installed $${CODE}$extension_id$${RESET}\n"
        echo "$(date): Successfully installed $extension_id from URL" >> "$log_file"
        rm -rf "$extension_temp_dir"
        return 0
      else
        printf "$${RED}❌ Invalid extension package$${RESET}\n"
        echo "$(date): Invalid extension package for $extension_id from URL - package.json not found" >> "$log_file"
        echo "$(date): Directory contents: $(ls -la "$extract_dir")" >> "$log_file"
        rm -rf "$extract_dir"
        rm -rf "$extension_temp_dir"
        return 1
      fi
    else
      printf "$${RED}❌ Failed to extract extension$${RESET}\n"
      echo "$(date): Failed to extract $extension_id from URL" >> "$log_file"
      rm -rf "$extract_dir"
      rm -rf "$extension_temp_dir"
      return 1
    fi
  else
    printf "$${RED}❌ Failed to download extension from URL$${RESET}\n"
    echo "$(date): Failed to download $extension_id from URL: $url" >> "$log_file"
    rm -rf "$extension_temp_dir"
    return 1
  fi
}

install_extensions_from_urls() {
  local urls="$1"
  local target_dir="$2"
  local temp_dir="$3"
  local log_file="$4"

  if [[ -z "$urls" ]]; then
    return 0
  fi

  printf "$${BOLD}🔗 Installing extensions from URLs...$${RESET}\n"

  echo "$urls" | tr ',' '\n' | while read -r url; do
    url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$url" ]; then
      install_extension_from_url "$url" "$target_dir" "$temp_dir" "$log_file"
    fi
  done
}

install_extensions_from_ids() {
  local extensions="$1"
  local target_dir="$2"
  local temp_dir="$3"
  local log_file="$4"

  if [[ -z "$extensions" ]]; then
    return 0
  fi

  printf "$${BOLD}🧩 Installing extensions from extension IDs...$${RESET}\n"

  echo "$extensions" | tr ',' '\n' | while read -r extension_id; do
    extension_id=$(echo "$extension_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$extension_id" ]; then
      local metadata_url
      metadata_url=$(generate_extension_url "$extension_id")
      if [ -n "$metadata_url" ]; then
        download_and_install_extension "$target_dir" "$extension_id" "$metadata_url" "$temp_dir" "$log_file"
      else
        printf "$${RED}❌ Invalid extension ID: $extension_id$${RESET}\n"
        echo "$(date): Invalid extension ID: $extension_id" >> "$log_file"
      fi
    fi
  done
}

main() {
  printf "$${BOLD}🚀 Starting extension installation for $${CODE}${IDE_TYPE}$${RESET} IDE...\n"

  for cmd in curl unzip timeout; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      printf "$${RED}❌ Missing required command: $cmd$${RESET}\n"
      return 1
    fi
  done

  local module_dir="$HOME/.vscode-desktop-core"
  local temp_dir="$module_dir/tmp"
  local logs_dir="$module_dir/logs"

  mkdir -p "$temp_dir" "$logs_dir"

  local log_file
  log_file="$logs_dir/extension-installation-$(date +%Y%m%d-%H%M%S).log"
  printf "$${BOLD}📝 Logging to: $${CODE}$log_file$${RESET}\n"

  local extensions_dir="${EXTENSIONS_DIR}"
  if [ "$${extensions_dir#\~}" != "$extensions_dir" ]; then
    extensions_dir="$HOME/$${extensions_dir#\~/}"
  fi

  printf "$${BOLD}📁 Using extensions directory: $${CODE}$extensions_dir$${RESET}\n"

  mkdir -p "$extensions_dir"
  if [[ ! -w "$extensions_dir" ]]; then
    printf "$${RED}❌ Extensions directory is not writable: $extensions_dir$${RESET}\n"
    return 1
  fi

  if [ -n "${EXTENSIONS_URLS}" ]; then
    install_extensions_from_urls "${EXTENSIONS_URLS}" "$extensions_dir" "$temp_dir" "$log_file"
  fi

  if [[ -n "${EXTENSIONS}" ]]; then
    install_extensions_from_ids "${EXTENSIONS}" "$extensions_dir" "$temp_dir" "$log_file"
  fi

  printf "$${BOLD}$${GREEN}✨ Extension installation completed for $${CODE}${IDE_TYPE}$${RESET}$${BOLD}$${GREEN}!$${RESET}\n"
  printf "$${BOLD}📁 Extensions installed to: $${CODE}$extensions_dir$${RESET}\n"
  printf "$${BOLD}📝 Log file: $${CODE}$log_file$${RESET}\n"
}

if [[ -n "${EXTENSIONS}" ]] || [[ -n "${EXTENSIONS_URLS}" ]]; then
  main
else
  printf "$${BOLD}ℹ️  No extensions to install for $${CODE}${IDE_TYPE}$${RESET}\n"
fi
