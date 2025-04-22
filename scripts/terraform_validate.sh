#!/bin/bash

set -euo pipefail

validate_terraform_directory() {
    local dir="$1"
    echo "Running \`terraform validate\` in $dir"
    pushd "$dir"
    terraform init -upgrade
    terraform validate
    popd
}

main() {
    # Get the directory of the script
    local script_dir=$(dirname "$(readlink -f "$0")")

    # Code assumes that registry directory will always be in same position
    # relative to the main script directory
    local registry_dir="$script_dir/../registry"

    # Get all subdirectories in the registry directory. Code assumes that
    # Terraform directories won't begin to appear until three levels deep into
    # the registry (e.g., registry/coder/modules/coder-login, which will then
    # have a main.tf file inside it)
    local subdirs=$(find "$registry_dir" -mindepth 3 -type d | sort)

    for dir in $subdirs; do
        # Skip over any directories that obviously don't have the necessary
        # files
        if test -f "$dir/main.tf"; then
            validate_terraform_directory "$dir"
        fi
    done
}

main
