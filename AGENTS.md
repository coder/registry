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

## Module Data Layout

All runtime data a module writes on the workspace MUST live under a single per-module root:

```
$HOME/.coder-modules/<namespace>/<module-name>/
```

For a Coder-owned module named `claude-code`, the root is `$HOME/.coder-modules/coder/claude-code/`.

Within that root, use these standard subdirectories:

| Subdirectory | Purpose                                   | Example                                                     |
| ------------ | ----------------------------------------- | ----------------------------------------------------------- |
| `logs/`      | Output from install, start, or any script | `$HOME/.coder-modules/coder/claude-code/logs/install.log`   |
| `scripts/`   | Scripts materialized at runtime (if any)  | `$HOME/.coder-modules/coder/claude-code/scripts/install.sh` |

- Name log files after the script that produced them (`install.sh` writes to `logs/install.log`, `start.sh` writes to `logs/start.log`).
- Always `mkdir -p` the target directory before writing; do not assume it exists.
- Do not write module runtime data to `$HOME` directly, to ad-hoc paths like `~/.<module>-module/`, or to `/tmp/` for anything that must survive the session.
- Tool-specific data (config files, caches, state, etc.) lives wherever the tool expects; only standardize paths the module itself controls.
- READMEs and tests should reference paths under this root so troubleshooting has one place to look.
- New modules MUST follow this layout. Existing modules should migrate to it when they are next touched.

## Use `coder-utils` for Script Orchestration

For any new module that runs scripts (or when reworking an existing one), use the [`coder-utils`](registry/coder/modules/coder-utils) module to orchestrate `pre_install`, `install`, `post_install`, and `start` scripts instead of hand-rolling `coder_script` resources.

- `coder-utils` handles script ordering via `coder exp sync`, materializes scripts under `module_directory/scripts/` (prefixed with `${agent_name}-utils-`), and writes logs to `module_directory/logs/` automatically, which aligns with the Module Data Layout above.
- Set `module_directory = "$HOME/.coder-modules/<namespace>/<module-name>"` so the standard root, `scripts/`, and `logs/` subdirectories fall out for free.

## Code Style

- Every module MUST have `.tftest.hcl` tests; optional `main.test.ts` for container/script tests
- README frontmatter: `display_name`, `description`, `icon`, `verified: false`, `tags`
- Use semantic versioning; bump version via script when modifying modules
- Docker tests require Linux or Colima/OrbStack (not Docker Desktop)
- Use `tf` (not `hcl`) for code blocks in README; use relative icon paths (e.g., `../../../../.icons/`)
- **Do NOT include input/output variable tables in module or template READMEs.** The registry automatically generates these from the Terraform source (e.g., variable and output blocks in `main.tf`). Adding them to the README is redundant and creates maintenance drift.
- Usage examples (e.g., a `module "..." { }` block) are encouraged, but not tables enumerating inputs/outputs.

## PR Review Checklist

- Version bumped via `.github/scripts/version-bump.sh` if module changed (patch=bugfix, minor=feature, major=breaking)
- Breaking changes documented: removed inputs, changed defaults, new required variables
- New variables have sensible defaults to maintain backward compatibility
- Tests pass (`bun run tftest`, `bun run tstest`); add diagnostic logging for test failures
- README examples updated with new version number; tooltip/behavior changes noted
- Shell scripts handle errors gracefully (use `|| echo "Warning..."` for non-fatal failures)
- No hardcoded values that should be configurable; no absolute URLs (use relative paths)
- If AI-assisted: include model and tool/agent name at footer of PR body (e.g., "Generated with [Amp](thread-url) using Claude")
