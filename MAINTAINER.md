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

- [ ] All required files (`main.tf`, `main.test.ts`, `README.md`)
- [ ] Proper frontmatter in README
- [ ] Working tests (`bun test`)
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

### Create Release Tags

After merging a PR:

1. Get the new version from the PR (shown as `old → new`)
2. Checkout the merge commit and create the tag:

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
maintainer_github: "username"
partner_github: "partner-name" # Optional - For official partner modules
verified: false # Optional - Set by maintainers only
tags: ["tag1", "tag2"]
```

### Namespace Frontmatter (Required)

```yaml
display_name: "Your Name"
bio: "Brief description of who you are and what you do"
avatar_url: "./.images/avatar.png"
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
