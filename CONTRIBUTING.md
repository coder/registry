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

- Basic Terraform knowledge (for module development)
- Terraform installed ([installation guide](https://developer.hashicorp.com/terraform/install))
- Docker (for running tests)

### Install Dependencies

Install Bun:

```bash
curl -fsSL https://bun.sh/install | bash
```

Install project dependencies:

```bash
bun install
```

### Understanding Namespaces

All modules are organized under `/registry/[namespace]/modules/`. Each contributor gets their own namespace (e.g., `/registry/your-username/modules/`). If a namespace is taken, choose a different unique namespace, but you can still use any display name on the Registry website.

### Images and Icons

- **Namespace avatars**: Must be named `avatar.png` or `avatar.svg` in `/registry/[namespace]/.images/`
- **Module screenshots/demos**: Use `/registry/[namespace]/.images/` for module-specific images
- **Module icons**: Use the shared `/.icons/` directory at the root for module icons

---

## Creating a New Module

### 1. Create Your Namespace (First Time Only)

If you're a new contributor, create your namespace:

```bash
mkdir -p registry/[your-username]
mkdir -p registry/[your-username]/.images
```

#### Add Your Avatar

Every namespace must have an avatar. We recommend using your GitHub avatar:

1. Download your GitHub avatar from `https://github.com/[your-username].png`
2. Save it as `avatar.png` in `registry/[your-username]/.images/`
3. This gives you a properly sized, square image that's already familiar to the community

The avatar must be:

- Named exactly `avatar.png` or `avatar.svg`
- Square image (recommended: 400x400px minimum)
- Supported formats: `.png` or `.svg` only

#### Create Your Namespace README

Create `registry/[your-username]/README.md`:

```markdown
---
display_name: "Your Name"
bio: "Brief description of who you are and what you do"
avatar_url: "./.images/avatar.png"
github: "your-username"
linkedin: "https://www.linkedin.com/in/your-username" # Optional
website: "https://yourwebsite.com" # Optional
support_email: "you@example.com" # Optional
status: "community"
---

# Your Name

Brief description of who you are and what you do.
```

> **Note**: The `avatar_url` must point to `./.images/avatar.png` or `./.images/avatar.svg`.

### 2. Generate Module Files

```bash
./scripts/new_module.sh [your-username]/[module-name]
cd registry/[your-username]/modules/[module-name]
```

This script generates:

- `main.tf` - Terraform configuration template
- `README.md` - Documentation template with frontmatter
- `run.sh` - Script for module execution (can be deleted if not required)

### 3. Build Your Module

1. **Edit `main.tf`** to implement your module's functionality
2. **Update `README.md`** with:
   - Accurate description and usage examples
   - Correct icon path (usually `../../../../.icons/your-icon.svg`)
   - Proper tags that describe your module
3. **Create `main.test.ts`** to test your module
4. **Add any scripts** or additional files your module needs

### 4. Test and Submit

```bash
# Test your module
bun test -t 'module-name'

# Format code
bun fmt

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
# Test a specific module
bun test -t 'module-name'

# Test all modules
bun test
```

### 4. Maintain Backward Compatibility

- New variables should have default values
- Don't break existing functionality
- Test that minimal configurations still work

---

## Submitting Changes

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

Module README frontmatter must include:

```yaml
---
display_name: "Module Name" # Required - Name shown on Registry website
description: "What it does" # Required - Short description
icon: "../../../../.icons/tool.svg" # Required - Path to icon file
verified: false # Optional - Set by maintainers only
tags: ["tag1", "tag2"] # Required - Array of descriptive tags
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
5. **Not running** `bun fmt` before submitting

Happy contributing! 🚀
