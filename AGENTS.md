# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

## Project Overview

The Coder Registry is a community-driven repository for Terraform modules and templates that extend Coder workspaces. It's organized with:

- **Modules**: Individual components and tools (IDEs, auth integrations, dev tools)
- **Templates**: Complete workspace configurations for different platforms
- **Namespaces**: Each contributor has their own namespace under `/registry/[namespace]/`

## Common Development Commands

### Formatting

```bash
bun run fmt    # Format all code (Prettier + Terraform)
bun run fmt:ci # Check formatting (CI mode)
```

### Testing

```bash
# Test all modules with .tftest.hcl files
bun run test

# Test specific module (from module directory)
terraform init -upgrade
terraform test -verbose

# Validate Terraform syntax
./scripts/terraform_validate.sh
```

### Module Creation

```bash
# Generate new module scaffold
./scripts/new_module.sh namespace/module-name
```

### TypeScript Testing & Setup

The repository uses Bun for TypeScript testing with utilities:

- `test/test.ts` - Testing utilities for container management and Terraform operations
- `setup.ts` - Test cleanup (removes .tfstate files and test containers)
- Container-based testing with Docker for module validation

## Architecture & Organization

### Directory Structure

```
registry/[namespace]/
├── README.md          # Contributor info with frontmatter
├── .images/           # Namespace avatar (avatar.png/svg)
├── modules/           # Individual components
│   └── [module]/      # Each module has main.tf, README.md, tests
└── templates/         # Complete workspace configs
    └── [template]/    # Each template has main.tf, README.md
```

### Key Components

**Module Structure**: Each module contains:

- `main.tf` - Terraform implementation
- `README.md` - Documentation with YAML frontmatter
- `.tftest.hcl` - Terraform test files (required)
- `run.sh` - Optional startup script

**Template Structure**: Each template contains:

- `main.tf` - Complete Coder template configuration
- `README.md` - Documentation with YAML frontmatter
- Additional configs, scripts as needed

### README Frontmatter Requirements

All modules/templates require YAML frontmatter:

```yaml
---
display_name: "Module Name"
description: "Brief description"
icon: "../../../../.icons/tool.svg"
verified: false
tags: ["tag1", "tag2"]
---
```

## Testing Requirements

### Module Testing

- Every module MUST have `.tftest.hcl` test files
- Optional `main.test.ts` files for container-based testing or complex business logic validation
- Tests use Docker containers with `--network=host` flag
- Linux required for testing (Docker Desktop on macOS/Windows won't work)
- Use Colima or OrbStack on macOS instead of Docker Desktop

### Test Utilities

The `test/test.ts` file provides:

- `runTerraformApply()` - Execute Terraform with variables
- `executeScriptInContainer()` - Run coder_script resources in containers
- `testRequiredVariables()` - Validate required variables
- Container management functions

## Validation & Quality

### Automated Validation

The Go validation tool (`cmd/readmevalidation/`) checks:

- Repository structure integrity
- Contributor README files
- Module and template documentation
- Frontmatter format compliance

### Versioning

Use semantic versioning for modules:

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes

## Dependencies & Tools

### Required Tools

- **Terraform** - Module development and testing
- **Docker** - Container-based testing
- **Bun** - JavaScript runtime for formatting/scripts
- **Go 1.23+** - Validation tooling

### Development Dependencies

- Prettier with Terraform and shell plugins
- TypeScript for test utilities
- Various npm packages for documentation processing

## Workflow Notes

### Contributing Process

1. Create namespace (first-time contributors)
2. Generate module/template files using scripts
3. Implement functionality and tests
4. Run formatting and validation
5. Submit PR with appropriate template

### Testing Workflow

- All modules must pass `terraform test`
- Use `bun run test` for comprehensive testing
- Format code with `bun run fmt` before submission
- Manual testing recommended for templates

### Namespace Management

- Each contributor gets unique namespace
- Namespace avatar required (avatar.png/svg in .images/)
- Namespace README with contributor info and frontmatter
