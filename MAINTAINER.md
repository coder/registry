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

## Daily Tasks

### Review PRs

Check that PRs have:

- [ ] All required files (`main.tf`, `main.test.ts`, `README.md`)
- [ ] Proper frontmatter in README
- [ ] Working tests (`bun test`)
- [ ] Formatted code (`bun run fmt`)

### Validate READMEs

```bash
go build ./cmd/readmevalidation && ./readmevalidation
```

## Releases

### Create Release Tags

After merging a PR:

```bash
git checkout MERGE_COMMIT_ID
git tag -a "release/$namespace/$module/v$version" -m "Release $namespace/$module v$version"
git push origin release/$namespace/$module/v$version
```

### Version Numbers

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes

## README Requirements

### Module Frontmatter (Required)

```yaml
display_name: "Tool Name"
description: "What it does"
icon: "path/to/icon.svg"
maintainer_github: "username"
verified: false # true for verified modules
tags: ["tag1", "tag2"]
```

### Namespace Frontmatter (Required)

```yaml
display_name: "Your Name"
bio: "Brief description"
github: "username"
status: "community" # or "partner", "official"
```

## Common Issues

- **README validation fails**: Check YAML syntax, ensure h1 header after frontmatter
- **Tests fail**: Ensure Docker with `--network=host`, check Terraform syntax
- **Wrong file structure**: Use `./scripts/new_module.sh` for new modules

## Emergency

### Revert Release

```bash
git tag -d release/$namespace/$module/v$version
git push origin :refs/tags/release/$namespace/$module/v$version
```

That's it. Keep it simple.
