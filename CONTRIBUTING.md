# Contributing to the Coder Registry

Welcome! This guide covers how to contribute to the Coder Registry, whether you're creating a new module or improving an existing one.

## What is the Coder Registry?

The Coder Registry is a collection of Terraform modules and templates for Coder workspaces. Modules provide IDEs, authentication integrations, development tools, and other workspace functionality. Templates provide complete workspace configurations for different platforms and use cases that appear as community templates on the registry website.

## Types of Contributions

- **[New Modules](#creating-a-new-module)** - Add support for a new tool or functionality
- **[New Templates](#creating-a-new-template)** - Create complete workspace configurations
- **[Existing Modules](#contributing-to-existing-modules)** - Fix bugs, add features, or improve documentation
- **[Existing Templates](#contributing-to-existing-templates)** - Improve workspace templates
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

All modules and templates are organized under `/registry/[namespace]/`. Each contributor gets their own namespace with both modules and templates directories:

```
registry/[namespace]/
├── modules/         # Individual components and tools
└── templates/       # Complete workspace configurations
```

For example: `/registry/your-username/modules/` and `/registry/your-username/templates/`. If a namespace is taken, choose a different unique namespace, but you can still use any display name on the Registry website.

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
avatar: "./.images/avatar.png"
github: "your-username"
linkedin: "https://www.linkedin.com/in/your-username" # Optional
website: "https://yourwebsite.com" # Optional
support_email: "you@example.com" # Optional
status: "community"
---

# Your Name

Brief description of who you are and what you do.
```

> **Note**: The `avatar` must point to `./.images/avatar.png` or `./.images/avatar.svg`.

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

## Creating a New Template

Templates are complete Coder workspace configurations that users can deploy directly. Unlike modules (which are components), templates provide full infrastructure definitions for specific platforms or use cases.

### Template Structure

Templates follow the same namespace structure as modules but are located in the `templates` directory:

```
registry/[your-username]/templates/[template-name]/
├── main.tf          # Complete Terraform configuration
├── README.md        # Documentation with frontmatter
├── [additional files] # Scripts, configs, etc.
```

### 1. Create Your Template Directory

```bash
mkdir -p registry/[your-username]/templates/[template-name]
cd registry/[your-username]/templates/[template-name]
```

### 2. Create Template Files

#### main.tf

Your `main.tf` should be a complete Coder template configuration including:

- Required providers (coder, and your infrastructure provider)
- Coder agent configuration
- Infrastructure resources (containers, VMs, etc.)
- Registry modules for IDEs, tools, and integrations

Example structure:

```terraform
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    # Add your infrastructure provider (docker, aws, etc.)
  }
}

# Coder data sources
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Coder agent
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    # Startup commands here
  EOT
}

# Registry modules for IDEs, tools, and integrations
module "code-server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

# Your infrastructure resources
# (Docker containers, AWS instances, etc.)
```

#### README.md

Create documentation with proper frontmatter:

```markdown
---
display_name: "Template Name"
description: "Brief description of what this template provides"
icon: "../../../../.icons/platform.svg"
verified: false
tags: ["platform", "use-case", "tools"]
---

# Template Name

Describe what the template provides and how to use it.

Include any setup requirements, resource information, or usage notes that users need to know.
```

### 3. Test Your Template

Templates should be tested to ensure they work correctly. Test with Coder:

```bash
cd registry/[your-username]/templates/[template-name]
coder templates push [template-name] -d .
```

### 4. Template Best Practices

- **Use registry modules**: Leverage existing modules for IDEs, tools, and integrations
- **Provide sensible defaults**: Make the template work out-of-the-box
- **Include metadata**: Add useful workspace metadata (CPU, memory, disk usage)
- **Document prerequisites**: Clearly explain infrastructure requirements
- **Use variables**: Allow customization of common settings
- **Follow naming conventions**: Use descriptive, consistent naming

### 5. Template Guidelines

- Templates appear as "Community Templates" on the registry website
- Include proper error handling and validation
- Test with Coder before submitting
- Document any required permissions or setup steps
- Use semantic versioning in your README frontmatter

---

## Contributing to Existing Templates

### 1. Types of Template Improvements

**Bug fixes:**

- Fix infrastructure provisioning issues
- Resolve agent connectivity problems
- Correct resource naming or tagging

**Feature additions:**

- Add new registry modules for additional functionality
- Include additional infrastructure options
- Improve startup scripts or automation

**Platform updates:**

- Update base images or AMIs
- Adapt to new platform features
- Improve security configurations

**Documentation:**

- Clarify prerequisites and setup steps
- Add troubleshooting guides
- Improve usage examples

### 2. Testing Template Changes

Testing template modifications thoroughly is necessary. Test with Coder:

```bash
coder templates push test-[template-name] -d .
```

### 3. Maintain Compatibility

- Don't remove existing variables without clear migration path
- Preserve backward compatibility when possible
- Test that existing workspaces still function
- Document any breaking changes clearly

---

## Contributing to Existing Modules

### 1. Make Your Changes

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

### 2. Test Your Changes

```bash
# Test a specific module
bun test -t 'module-name'

# Test all modules
bun test
```

### 3. Maintain Backward Compatibility

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
- **New Template**: Use `?template=new_template.md`
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

### Every Template Must Have

- `main.tf` - Complete Terraform configuration
- `README.md` - Documentation with frontmatter

Templates don't require test files like modules do, but should be manually tested before submission.

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

When you modify a module, you need to update its version number in the README. Understanding version numbers helps you describe the impact of your changes:

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing types)

### Updating Module Versions

If your changes require a version bump, use the version bump script:

```bash
# For bug fixes
./.github/scripts/version-bump.sh patch

# For new features
./.github/scripts/version-bump.sh minor

# For breaking changes
./.github/scripts/version-bump.sh major
```

The script will:

1. Detect which modules you've modified
2. Calculate the new version number
3. Update all version references in the module's README
4. Show you a summary of changes

**Important**: Only run the version bump script if your changes require a new release. Documentation-only changes don't need version updates.

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

- **Examples**: Check `/registry/coder/modules/` for well-structured modules and `/registry/coder/templates/` for complete templates
- **Issues**: Open an issue for technical problems
- **Community**: Reach out to the Coder community for questions

## Common Pitfalls

1. **Missing frontmatter** in README
2. **No tests** or broken tests
3. **Hardcoded values** instead of variables
4. **Breaking changes** without defaults
5. **Not running** `bun fmt` before submitting

Happy contributing! 🚀
