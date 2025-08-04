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

# Check if template name is in the format <namespace>/<template_name>
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

# Create template directory
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
  sed -i '' "s/NAMESPACE/${NAMESPACE}/g" README.md
  sed -i '' "s/PLATFORM_NAME/Docker/g" main.tf
else
  # Linux
  sed -i "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" main.tf
  sed -i "s/TEMPLATE_NAME/${TEMPLATE_NAME}/g" README.md
  sed -i "s/NAMESPACE/${NAMESPACE}/g" README.md
  sed -i "s/PLATFORM_NAME/Docker/g" main.tf
fi

echo ""
echo "✅ Template created successfully!"
echo ""
echo "📁 Template location: registry/${NAMESPACE}/templates/${TEMPLATE_NAME}"
echo ""
echo "📝 Next steps:"
echo "   1. Edit main.tf to implement your infrastructure"
echo "   2. Update README.md with accurate documentation"
echo "   3. Test your template with: coder templates push ${TEMPLATE_NAME} -d ."
echo "   4. Commit and create a pull request"
echo ""
echo "📖 See CONTRIBUTING.md for detailed guidance on creating templates"
