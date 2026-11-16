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
- [ ] Version label: `version:patch`, `version:minor`, or `version:major`

### Version Guidelines

When reviewing PRs, ensure the version change follows semantic versioning:

- **Patch** (1.2.3 → 1.2.4): Bug fixes
- **Minor** (1.2.3 → 1.3.0): New features, adding inputs
- **Major** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing types)

PRs should clearly indicate the intended version change (e.g., `v1.2.3 → v1.2.4`) and include the appropriate label: `version:patch`, `version:minor`, or `version:major`.
The “Version Bump” CI uses this label to validate required updates (README version refs, etc.).

### Validate READMEs

```bash
go build ./cmd/readmevalidation && ./readmevalidation
```

## Making a Release

Release tags (`release/<namespace>/<module>/vX.Y.Z`) are created only by the
`coder-registry-publisher` GitHub App, through the **Tag releases** workflow. Nobody can push,
move or delete tags by hand, admins included. Every tag points at a commit on `main`, so every
published version went through a reviewed pull request.

After merging PRs that bump module versions in their READMEs (the source of truth):

1. Dispatch the workflow from `main`:

   ```bash
   gh workflow run tag-release.yaml --repo coder/registry --ref main
   ```

   or Actions > Tag releases > Run workflow.

2. The **Plan tags** job lists the tags it will create, with the commit each points at, in the
   run summary. Each tag points at the latest merge commit that changed that module, not at HEAD.

3. Another registry maintainer (`@coder/registry-maintainers`; you can't approve your own run)
   checks the list and approves the `release-tags` deployment. The **Create tags** job then creates
   exactly those tags.

To preview locally (needs a full clone, not a shallow one):

```bash
git checkout main && git pull
./scripts/tag_release.sh --dry-run
```

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
