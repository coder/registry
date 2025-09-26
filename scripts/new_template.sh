#!/usr/bin/env bash

# This script creates a new sample template directory with required files
# Run it like: ./scripts/new_template.sh my-namespace/my-template

TEMPLATE_ARG=$1

# Check if they are in the root directory
if [ ! -d "registry" ]; then
  echo "Please run this script from the root directory of the repository"
  echo "Usage: ./scripts/new_template.sh <namespace>/<template_name>"
  exit 1
fi

# check if template name is in the format <namespace>/<template_name>
if ! [[ "$TEMPLATE_ARG" =~ ^[a-z0-9_-]+/[a-z0-9_-]+$ ]]; then
  echo "Template name must be in the format <namespace>/<template_name>"
  echo "Usage: ./scripts/new_template.sh <namespace>/<template_name>"
  exit 1
fi

# Extract the namespace and template name
NAMESPACE=$(echo "$TEMPLATE_ARG" | cut -d'/' -f1)
TEMPLATE_NAME=$(echo "$TEMPLATE_ARG" | cut -d'/' -f2)

# Check if the template already exists
if [ -d "registry/$NAMESPACE/templates/$TEMPLATE_NAME" ]; then
  echo "Template at registry/$NAMESPACE/templates/$TEMPLATE_NAME already exists"
  echo "Please choose a different name"
  exit 1
fi

# Create namespace directory if it doesn't exist
if [ ! -d "registry/$NAMESPACE" ]; then
  echo "Creating namespace directory: registry/$NAMESPACE"
  mkdir -p "registry/$NAMESPACE"

  # Create namespace README if it doesn't exist
  if [ ! -f "registry/$NAMESPACE/README.md" ]; then
    echo "Creating namespace README: registry/$NAMESPACE/README.md"
    cp "examples/namespace/README.md" "registry/$NAMESPACE/README.md"

    # Replace NAMESPACE_NAME placeholder in the README
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sed -i '' "s/NAMESPACE_NAME/${NAMESPACE}/g" "registry/$NAMESPACE/README.md"
    else
      # Linux
      sed -i "s/NAMESPACE_NAME/${NAMESPACE}/g" "registry/$NAMESPACE/README.md"
    fi
  fi
fi

# Create the template directory structure
mkdir -p "registry/${NAMESPACE}/templates/${TEMPLATE_NAME}"

# Copy required files from the example template
cp -r examples/templates/* "registry/${NAMESPACE}/templates/${TEMPLATE_NAME}/"

# Change to template directory
cd "registry/${NAMESPACE}/templates/${TEMPLATE_NAME}"

# Detect OS and replace placeholders
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" main.tf
  sed -i '' "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" README.md
else
  # Linux
  sed -i "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" main.tf
  sed -i "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" README.md
fi

echo "Template scaffolded successfully at registry/${NAMESPACE}/templates/${TEMPLATE_NAME}"
echo "Next steps:"
echo "1. Edit main.tf to add your infrastructure resources"
echo "2. Update README.md with template-specific information"
echo "3. Test your template with 'coder templates push'"
echo "4. Consider adding an icon at .icons/${TEMPLATE_NAME}.svg"
