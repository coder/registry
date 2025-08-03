# Template Linter

A command-line tool for validating Coder template README files.

## Features

- Validates README structure and required sections
- Checks content quality and completeness
- Provides improvement suggestions
- Supports single file or directory scanning
- JSON output option for CI/CD integration

## Installation

```bash
go install github.com/coder/registry/cmd/templatelint@latest
```

## Usage

```bash
# Lint a single README
templatelint -path ./registry/myuser/templates/mytemplate/README.md

# Lint all templates in a directory
templatelint -path ./registry/myuser/templates

# Lint and attempt to fix issues
templatelint -path ./README.md -fix

# Output results in JSON format
templatelint -path ./README.md -json
```

## Validation Rules

The linter checks:

1. Frontmatter requirements:
   - Required fields: display_name, description, icon, tags, platform, requirements, workload
   - Valid platform values
   - Non-empty requirements list

2. Required sections:
   - Prerequisites
   - Infrastructure/Resources
   - Usage/Examples
   - Cost and Permissions
   - Variables

3. Section content:
   - Minimum content length
   - Required patterns and keywords
   - Proper formatting
   - Complete information

## Example Output

```
Linting ./registry/myuser/templates/mytemplate/README.md:

[ERROR] Prerequisites:
  - Section must have at least 3 lines of content
  - Missing bullet points for requirements

[SUGGESTIONS] Infrastructure:
  - Detail all infrastructure components
  - Include resource specifications
  - List any dependencies between resources

✅ All other sections look good!
```

## Integration

### GitHub Actions

```yaml
name: Lint Template READMEs

on:
  pull_request:
    paths:
      - 'registry/*/templates/*/README.md'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-go@v2
        with:
          go-version: '1.21'
      - name: Install templatelint
        run: go install github.com/coder/registry/cmd/templatelint@latest
      - name: Lint READMEs
        run: templatelint -path ./registry -json
```

### Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/sh
files=$(git diff --cached --name-only | grep 'templates/.*/README.md$')
if [ -n "$files" ]; then
  templatelint -path "$files"
fi
```

## Contributing

Contributions are welcome! Please see the main repository's [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.
