# Contributing to the Coder Registry

Welcome! This guide covers how to contribute to the Coder Registry, whether you're creating a new module or improving an existing one.

## What is the Coder Registry?

The Coder Registry is a collection of Terraform modules that extend Coder workspaces with development tools like VS Code, Cursor, JetBrains IDEs, and more.

## Types of Contributions

- **[New Modules](#creating-a-new-module)** - Add support for a new tool or functionality
- **[Existing Modules](#contributing-to-existing-modules)** - Fix bugs, add features, or improve documentation
- **[Bug Reports](#reporting-issues)** - Report problems or request features

## Setup

### Prerequisites

- Git and GitHub account
- Basic Terraform knowledge (for module development)
- Terraform installed ([installation guide](https://developer.hashicorp.com/terraform/install))
- Docker (for running tests)

### Install Dependencies

Install Bun (test runner):

```bash
curl -fsSL https://bun.sh/install | bash
```

Restart your terminal or source your profile:

```bash
source ~/.bashrc
```

Install project dependencies:

```bash
bun install
```

> **Note**: This repository does not support Yarn. Please use Bun for all package management.

### Installing Go (Optional)

This step can be skipped if you are not working on any of the README validation logic. The validation will still run as part of CI.

Navigate to the [official Go installation page](https://golang.org/doc/install), and install the correct version for your operating system.

Once Go has been installed, verify the installation:

```bash
go version
```

### Understanding Namespaces

All modules are organized under `/registry/[namespace]/modules/`. Each contributor gets their own namespace (e.g., `/registry/your-username/modules/`). If a namespace is taken, choose a different unique namespace, but you can still use any display name on the Registry website.

### Images and Icons

- **Namespace avatars**: Place your avatar in `/registry/[namespace]/images/`
- **Module images**: Place other images in `/registry/[namespace]/images/` to avoid conflicts
- **Module icons**: Can go in the top-level `/.icons/` directory if used by multiple modules

---

## Creating a New Module

### 1. Create Your Namespace (First Time Only)

If you're a new contributor, create your namespace:

```bash
mkdir -p registry/[your-username]
mkdir -p registry/[your-username]/images
```

#### Add Your Avatar

Every namespace should have an avatar. Add your avatar image:

1. Add a square image (recommended: 400x400px minimum) to `registry/[your-username]/images/`
2. Supported formats: `.png`, `.jpg`, `.jpeg`, `.svg`
3. Name it something clear like `avatar.png` or `profile.jpg`

#### Create Your Namespace README

Create `registry/[your-username]/README.md`:

```markdown
---
display_name: "Your Name"
bio: "Brief description of what you do"
avatar_url: "./images/avatar.png"
github: "your-username"
status: "community"
---

# Your Name
```

> **Note**: The `avatar_url` should point to your avatar image relative to your namespace directory.

### 2. Generate Module Files

```bash
./scripts/new_module.sh [your-username]/[module-name]
cd registry/[your-username]/modules/[module-name]
```

### 3. Build Your Module

**Edit `main.tf`** - Your Terraform code:

```terraform
terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

resource "coder_script" "install" {
  agent_id = var.agent_id
  script   = file("${path.module}/run.sh")
}
```

**Update `README.md`** - Add proper frontmatter:

```markdown
---
display_name: "Tool Name"
description: "Brief description of what this module does"
icon: "../../../.icons/tool.svg"
maintainer_github: "your-username"
verified: false
tags: ["development", "tool"]
---

# Tool Name

Brief description and usage example.

## Usage

```tf
module "tool" {
  source   = "registry.coder.com/[username]/[module]/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```
```

**Write tests in `main.test.ts`**:
```typescript
import { runTerraformApply, runTerraformInit, testRequiredVariables } from "~test";

describe("module-name", () => {
  it("should have required variables", async () => {
    await testRequiredVariables(import.meta.dir);
  });

  it("should apply successfully", async () => {
    await runTerraformInit(import.meta.dir);
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-id",
    });
  });
});
```

### 4. Test and Submit

```bash
# Test your module
bun test

# Format code
bun run fmt

# Commit and create PR
git add .
git commit -m "Add [module-name] module"
git push origin your-branch
```

> **Important**: It is your responsibility to implement tests for every new module. Test your module locally before opening a PR. The testing suite requires Docker containers with the `--network=host` flag, which typically requires running tests on Linux (this flag doesn't work with Docker Desktop on macOS/Windows). macOS users can use [Colima](https://github.com/abiosoft/colima) or [OrbStack](https://orbstack.dev/) instead of Docker Desktop.

---

## Contributing to Existing Modules

### 1. Find the Module

```bash
find registry -name "*[module-name]*" -type d
```

### 2. Make Your Changes

**For bug fixes:**

- Reproduce the issue
- Fix the code in `main.tf`
- Add/update tests
- Update documentation if needed

**For new features:**

- Add new variables with sensible defaults
- Implement the feature
- Add tests for new functionality
- Update README with new variables

**For documentation:**

- Fix typos and unclear explanations
- Add missing variable documentation
- Improve usage examples

### 3. Test Your Changes

```bash
cd registry/[namespace]/modules/[module-name]

# Test the specific module
bun test

# Test all modules (from repo root)
bun test
```

### 4. Maintain Backward Compatibility

- New variables should have default values
- Don't break existing functionality
- Test that minimal configurations still work

---

## Submitting Changes

### Create a Pull Request

1. **Fork and branch:**

   ```bash
   git checkout -b fix/module-name-issue
   ```

2. **Commit with clear messages:**

   ```bash
   git commit -m "Fix version parsing in module-name"
   ```

3. **Open PR with:**
   - Clear title describing the change
   - What you changed and why
   - Any breaking changes

### Using PR Templates

We have different PR templates for different types of contributions. GitHub will show you options to choose from, or you can manually select:

- **New Module**: Use `?template=new_module.md` 
- **Bug Fix**: Use `?template=bug_fix.md`
- **Feature**: Use `?template=feature.md`
- **Documentation**: Use `?template=documentation.md`

Example: `https://github.com/coder/registry/compare/main...your-branch?template=new_module.md`

---

## Requirements

### Every Module Must Have

- `main.tf` - Terraform code
- `main.test.ts` - Working tests
- `README.md` - Documentation with frontmatter

### README Frontmatter

```yaml
---
display_name: "Module Name" # Required - Name shown on Registry website
description: "What it does" # Required - Short description for Registry
icon: "path/to/icon.svg" # Required - Path to icon file
maintainer_github: "your-username" # Required - Your GitHub username
verified: false # Optional - Set by Coder maintainers only
tags: ["tag1", "tag2"] # Required - Array of descriptive tags
partner_github: "partner-name" # Optional - For official partnerships only
---
```

### README Requirements

All README files must follow these rules:

- Must have frontmatter section with proper YAML
- Exactly one h1 header directly below frontmatter
- When increasing header levels, increment by one each time
- Use `tf` instead of `hcl` for code blocks

### Best Practices

- Use descriptive variable names and descriptions
- Include helpful comments
- Test all functionality
- Follow existing code patterns in the module

---

## README Validation

If you installed Go, you can validate README files locally:

```bash
go build ./cmd/readmevalidation && ./readmevalidation
```

---

## Versioning Guidelines

After your PR is merged, maintainers will handle the release. Understanding version numbers helps you describe the impact of your changes:

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing types)

**Important**: Always specify the version change in your PR (e.g., `v1.2.3 → v1.2.4`). This helps maintainers create the correct release tag.

---

## Reporting Issues

When reporting bugs, include:

- Module name and version
- Expected vs actual behavior
- Minimal reproduction case
- Error messages
- Environment details (OS, Terraform version)

---

## Getting Help

- **Examples**: Check `/registry/coder/modules/` for well-structured modules
- **Issues**: Open an issue for technical problems
- **Community**: Reach out to the Coder community for questions

## Common Pitfalls

1. **Missing frontmatter** in README
2. **No tests** or broken tests
3. **Hardcoded values** instead of variables
4. **Breaking changes** without defaults
5. **Not running** `bun run fmt` before submitting

Happy contributing! 🚀
