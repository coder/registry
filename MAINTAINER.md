# Maintainer Guide

Quick reference for maintaining the Coder Registry repository.

## Setup

Install Go for README validation:

```bash
# macOS
brew install go

# Linux
sudo apt install golang-go
```

## Reviewing a PR

Check that PRs have:

- [ ] All required files (`main.tf`, `README.md`, at least one `.tftest.hcl`)
- [ ] Proper frontmatter in README
- [ ] Working tests (`terraform test`)
- [ ] Formatted code (`bun run fmt`)
- [ ] Avatar image for new namespaces (`avatar.png` or `avatar.svg` in `.images/`)

### Version Guidelines

When reviewing PRs, ensure the version change follows semantic versioning:

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing types)

PRs should clearly indicate the version change (e.g., `v1.2.3 → v1.2.4`).

### Validate READMEs

```bash
go build ./cmd/readmevalidation && ./readmevalidation
```

## Making a Release

### Automated Tag and Release Process

After merging a PR, use the automated script to create and push release tags:

**Prerequisites:**

- Ensure all module versions are updated in their respective README files (the script uses this as the source of truth)
- Make sure you have the necessary permissions to push tags to the repository

**Steps:**

1. **Checkout the merge commit:**

   ```bash
   git checkout MERGE_COMMIT_ID
   ```

2. **Run the tag release script:**

   ```bash
   ./scripts/tag_release.sh
   ```

3. **Review and confirm:**
   - The script will automatically scan all modules in the registry
   - It will detect which modules need version bumps by comparing README versions to existing tags
   - A summary will be displayed showing which modules need tagging
   - Confirm the list is correct when prompted

4. **Automatic tagging:**
   - After confirmation, the script will automatically create all necessary release tags
   - Tags will be pushed to the remote repository
   - The script operates on the current checked-out commit

**Example output:**

```text
🔍 Scanning all modules for missing release tags...

📦 coder/code-server: v4.1.2 (needs tag)
✅ coder/dotfiles: v1.0.5 (already tagged)

## Tags to be created:
- `release/coder/code-server/v4.1.2`

❓ Do you want to proceed with creating and pushing these release tags?
Continue? [y/N]: y
```

### Manual Process (Fallback)

If the automated script fails, you can manually tag and release modules:

```bash
# Checkout the merge commit
git checkout MERGE_COMMIT_ID

# Create and push the release tag using the version from the PR
git tag -a "release/$namespace/$module/v$version" -m "Release $namespace/$module v$version"
git push origin release/$namespace/$module/v$version
```

Example: If PR shows `v1.2.3 → v1.2.4`, use `v1.2.4` in the tag.

### Publishing

Changes are automatically published to [registry.coder.com](https://registry.coder.com) after tags are pushed.

## README Requirements

### Module Frontmatter (Required)

```yaml
display_name: "Module Name"
description: "What it does"
icon: "../../../../.icons/tool.svg"
verified: false # Optional - Set by maintainers only
tags: ["tag1", "tag2"]
```

### Namespace Frontmatter (Required)

```yaml
display_name: "Your Name"
bio: "Brief description of who you are and what you do"
avatar: "./.images/avatar.png"
github: "username"
linkedin: "https://www.linkedin.com/in/username" # Optional
website: "https://yourwebsite.com" # Optional
support_email: "you@example.com" # Optional
status: "community" # or "partner", "official"
```

## Common Issues

- **README validation fails**: Check YAML syntax, ensure h1 header after frontmatter
- **Tests fail**: Ensure Docker with `--network=host`, check Terraform syntax
- **Wrong file structure**: Use `./scripts/new_module.sh` for new modules
- **Missing namespace avatar**: Must be `avatar.png` or `avatar.svg` in `.images/` directory
