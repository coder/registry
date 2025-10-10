# Development Container

This directory contains a Dev Container configuration that provides a complete development environment for the Coder Registry with all required dependencies pre-installed.

## What's Included

The dev container includes:

- **Bun** - JavaScript runtime and package manager (for formatting and scripts)
- **Terraform** - Infrastructure as code tool (for module development)
- **Docker** - Container runtime (for running tests with `--network=host`)
- **Git** - Version control
- **VS Code Extensions**:
  - HashiCorp Terraform
  - Bun for VS Code
  - Prettier

## Quick Start

### Using VS Code

1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open this repository in VS Code
3. When prompted, click "Reopen in Container" (or run the command "Dev Containers: Reopen in Container")
4. Wait for the container to build and dependencies to install
5. Start developing!

### Using GitHub Codespaces

1. Click the "Code" button on the GitHub repository
2. Select "Codespaces" tab
3. Click "Create codespace on main"
4. Wait for the environment to be ready
5. Start developing!

### Using Coder

You can also use this with Coder's `docker-devcontainer` template:

1. Create a new workspace using the `docker-devcontainer` template
2. Point it to this repository
3. Coder will automatically use the `.devcontainer/devcontainer.json` configuration

## What Happens on Startup

When the container is created, it automatically:

1. Installs Bun via the official installation script
2. Runs `bun install` to install all project dependencies
3. Sets up PATH to include Bun binaries
4. Mounts Docker socket for Docker-in-Docker support
5. Configures VS Code with recommended extensions and settings

## Development Workflow

Once inside the container, you can use all the standard commands:

```bash
# Format code
bun run fmt

# Run tests
bun run test

# Create a new module
./scripts/new_module.sh namespace/module-name

# Test a specific module
cd registry/namespace/modules/module-name
terraform init -upgrade
terraform test -verbose
```

## Notes

- The container uses `--network=host` flag which is required for Terraform tests
- Docker socket is mounted to support Docker-based tests
- All dependencies are installed automatically on container creation
- The environment is based on Ubuntu for maximum compatibility

## Troubleshooting

**Bun not found after container creation:**
- Restart the terminal or run: `source ~/.bashrc`
- The PATH should include `~/.bun/bin`

**Docker not working:**
- Ensure Docker is running on your host machine
- Check that Docker socket is properly mounted

**Tests failing:**
- Make sure you're using Linux or a compatible Docker runtime (Colima/OrbStack on macOS)
- Verify Docker has network access with `--network=host`

## Contributing

This dev container configuration is part of the Coder Registry repository. If you find issues or have suggestions for improvements, please open an issue or pull request!
