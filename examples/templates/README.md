---
display_name: TEMPLATE_NAME
description: Brief description of what this template provides
icon: ../../../../.icons/<A_RELEVANT_ICON>.svg
verified: false
tags: [platform, use-case, tools]
---

# TEMPLATE_NAME

<!-- Describe what this template provides and how to use it -->

This template creates a complete development environment with pre-configured tools and infrastructure.

## Features

- Feature 1
- Feature 2
- Feature 3

## Prerequisites

<!-- List any requirements for using this template -->

- Requirement 1
- Requirement 2

## Infrastructure

<!-- Describe the infrastructure this template creates -->

This template provisions:

- Resource type 1
- Resource type 2
- Estimated cost: $X.XX/month

## Usage

To use this template:

1. Clone this repository or download the template directory
2. Navigate to the template directory:
   ```bash
   cd registry/NAMESPACE/templates/TEMPLATE_NAME
   ```
3. Push the template to your Coder instance:
   ```bash
   coder templates push TEMPLATE_NAME -d .
   ```
4. Create a workspace using this template in your Coder dashboard

## Variables

<!-- Document any template variables -->

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `variable_name` | Description | `default_value` | Yes/No |

## Registry Modules Used

This template includes the following registry modules:

- [`coder/code-server`](https://registry.coder.com/modules/code-server) - VS Code in the browser
- [`coder/git-config`](https://registry.coder.com/modules/git-config) - Git configuration

## Troubleshooting

### Common Issues

**Issue 1**: Description
- Solution: How to fix

**Issue 2**: Description  
- Solution: How to fix

### Support

For additional support:
- Check the [Coder documentation](https://coder.com/docs)
- Join the [Coder Discord](https://discord.gg/coder)
- Open an issue in this repository
