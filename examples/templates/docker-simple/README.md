---
display_name: "Docker Simple"
description: "A simple Docker-based development environment with VS Code"
icon: "../../../../../.icons/docker.svg"
verified: false
tags: ["docker", "vscode", "simple"]
---

# Docker Simple Template

A straightforward Docker-based development environment with VS Code (code-server) and essential development tools.

## Features

- Ubuntu-based Docker container
- VS Code (code-server) in the browser
- Git configuration
- Dotfiles support
- Resource monitoring

## Prerequisites

- Docker Engine running on the Coder host
- No additional infrastructure required

## Infrastructure

This template provisions:

- Single Docker container running Ubuntu
- Estimated cost: Free (uses local Docker)

## Usage

To use this template:

1. Clone this repository or download the template directory
2. Navigate to the template directory:
   ```bash
   cd registry/examples/templates/docker-simple
   ```
3. Push the template to your Coder instance:
   ```bash
   coder templates push docker-simple -d .
   ```
4. Create a workspace using this template in your Coder dashboard

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `docker_image` | Docker image to use | `codercom/enterprise-base:ubuntu` | No |

## Registry Modules Used

This template includes the following registry modules:

- [`coder/code-server`](https://registry.coder.com/modules/code-server) - VS Code in the browser
- [`coder/git-config`](https://registry.coder.com/modules/git-config) - Git configuration
- [`coder/dotfiles`](https://registry.coder.com/modules/dotfiles) - Dotfiles synchronization

## Troubleshooting

### Common Issues

**Container fails to start**: 
- Ensure Docker is running on the Coder host
- Check Docker image availability

**VS Code doesn't load**:
- Wait for the container to fully start
- Check agent logs in the Coder dashboard

### Support

For additional support:
- Check the [Coder documentation](https://coder.com/docs)
- Join the [Coder Discord](https://discord.gg/coder)
- Open an issue in this repository
