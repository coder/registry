#!/usr/bin/env bash

# This scripts creates a new sample moduledir with required files
# Run it like : ./scripts/new_module.sh my-namespace/my-module

MODULE_ARG=$1

# Check if they are in the root directory
if [ ! -d "registry" ]; then
  echo "Please run this script from the root directory of the repository"
  echo "Usage: ./scripts/new_module.sh <namespace>/<module_name>"
  exit 1
fi

# check if module name is in the format <namespace>/<module_name>
if ! [[ "$MODULE_ARG" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then
  echo "Module name must be in the format <namespace>/<module_name>"
  echo "Usage: ./scripts/new_module.sh <namespace>/<module_name>"
  exit 1
fi

# Extract the namespace and module name
NAMESPACE=$(echo "$MODULE_ARG" | cut -d'/' -f1)
MODULE_NAME=$(echo "$MODULE_ARG" | cut -d'/' -f2)

# Check if the module already exists
if [ -d "registry/$NAMESPACE/modules/$MODULE_NAME" ]; then
  echo "Module at registry/$NAMESPACE/modules/$MODULE_NAME already exists"
  echo "Please choose a different name"
  exit 1
fi
mkdir -p "registry/${NAMESPACE}/modules/${MODULE_NAME}"

# Copy required files from the example module
cp -r examples/modules/* "registry/${NAMESPACE}/modules/${MODULE_NAME}/"

# Change to module directory
cd "registry/${NAMESPACE}/modules/${MODULE_NAME}"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/MODULE_NAME/${MODULE_NAME}/g" main.tf
  sed -i '' "s/MODULE_NAME/${MODULE_NAME}/g" README.md
else
  # Linux
  sed -i "s/MODULE_NAME/${MODULE_NAME}/g" main.tf
  sed -i "s/MODULE_NAME/${MODULE_NAME}/g" README.md
fi

# Make run.sh executable
chmod +x run.sh
