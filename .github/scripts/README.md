# GitHub Scripts

This directory contains reusable scripts for GitHub Actions workflows.

## version-bump.sh

Extracts version bump logic from GitHub Actions workflows into a reusable script.

### Usage

```bash
./version-bump.sh <bump_type> [base_ref]
```

**Parameters:**
- `bump_type`: Type of version bump (`patch`, `minor`, or `major`)
- `base_ref`: Base reference for diff comparison (default: `origin/main`)

### Examples

```bash
# Bump patch version for modules changed since origin/main
./version-bump.sh patch

# Bump minor version for modules changed since a specific commit
./version-bump.sh minor abc123

# Bump major version for modules changed since a specific branch
./version-bump.sh major origin/develop
```

### What it does

1. **Detects modified modules** from git diff changes
2. **Gets current version** from latest release tag or README
3. **Calculates new version** based on bump type
4. **Updates README versions** in module documentation
5. **Provides summary** of changes and next steps

### Version Detection

- **Tagged modules**: Uses latest `release/namespace/module/vX.Y.Z` tag
- **Untagged modules**: Extracts version from README `version = "X.Y.Z"` 
- **New modules**: Start from v1.0.0

### Exit Codes

- `0`: Success (with or without changes)
- `1`: Error (invalid arguments, no modules found, invalid version format, etc.)

### Integration with GitHub Actions

This script is designed to be called from GitHub Actions workflows. See `.github/workflows/version-bump.yaml` for an example implementation that:

- Triggers on PR labels (`version:patch`, `version:minor`, `version:major`)
- Runs the script with appropriate parameters
- Commits any README changes
- Comments on the PR with results

### Notes

- Only updates READMEs that contain version references matching the module source
- Warns about modules missing proper git tags
- Follows semantic versioning (X.Y.Z format)
- Validates all version components are numeric