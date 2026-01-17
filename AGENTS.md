# AGENTS.md

Coder Registry: Terraform modules/templates for Coder workspaces under `registry/[namespace]/modules/` and `registry/[namespace]/templates/`.

## Commands

```bash
bun run fmt                                           # Format code (Prettier + Terraform) - run before commits
bun run tftest                                        # Run all Terraform tests
bun run tstest                                        # Run all TypeScript tests
terraform init -upgrade && terraform test -verbose    # Test single module (run from module dir)
bun test main.test.ts                                 # Run single TS test (from module dir)
./scripts/terraform_validate.sh                       # Validate Terraform syntax
./scripts/new_module.sh ns/name                       # Create new module scaffold
.github/scripts/version-bump.sh patch | minor | major # Bump module version after changes
```

## Structure

- **Modules**: `registry/[ns]/modules/[name]/` with `main.tf`, `README.md` (YAML frontmatter), `.tftest.hcl` (required)
- **Templates**: `registry/[ns]/templates/[name]/` with `main.tf`, `README.md`
- **Validation**: `cmd/readmevalidation/` (Go) validates structure/frontmatter; URLs must be relative, not absolute

## Code Style

- Every module MUST have `.tftest.hcl` tests; optional `main.test.ts` for container/script tests
- README frontmatter: `display_name`, `description`, `icon`, `verified: false`, `tags`
- Use semantic versioning; bump version via script when modifying modules
- Docker tests require Linux or Colima/OrbStack (not Docker Desktop)
- Use `tf` (not `hcl`) for code blocks in README; use relative icon paths (e.g., `../../../../.icons/`)

## PR Review Checklist

- Version bumped via `.github/scripts/version-bump.sh` if module changed (patch=bugfix, minor=feature, major=breaking)
- Breaking changes documented: removed inputs, changed defaults, new required variables
- New variables have sensible defaults to maintain backward compatibility
- Tests pass (`bun run tftest`, `bun run tstest`); add diagnostic logging for test failures
- README examples updated with new version number; tooltip/behavior changes noted
- Shell scripts handle errors gracefully (use `|| echo "Warning..."` for non-fatal failures)
- No hardcoded values that should be configurable; no absolute URLs (use relative paths)
- If AI-assisted: include model and tool/agent name at footer of PR body (e.g., "Generated with [Amp](thread-url) using Claude")
