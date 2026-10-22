# AGENTS.md

Coder Registry: Terraform modules/templates for Coder workspaces under `registry/[namespace]/modules/` and `registry/[namespace]/templates/`.

## Commands

```bash
bun run fmt                                           # Format code (Prettier + Terraform) - run before commits
bun run check:terraform                               # Run all Terraform tests
bun run check:typescript                              # Run all TypeScript tests
bun check                                             # Run all tests + validation (validate, shellcheck, terraform, typescript)
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

- `coder-utils` handles script ordering via `coder exp sync`, materializes scripts under `module_directory/scripts/` (e.g., `install.sh`, `start.sh`), and writes logs to `module_directory/logs/` automatically, which aligns with the Module Data Layout above.
- Set `module_directory = "$HOME/.coder-modules/<namespace>/<module-name>"` so the standard root, `scripts/`, and `logs/` subdirectories fall out for free.

### Passing scripts to `coder-utils`

Store each script as a `.tftpl` file under `scripts/`. Render it at **plan time** in a `locals` block using `templatefile()`, then pass the rendered string directly to the `coder-utils` module.

**Encoding rules for template variables:**

| Value type                            | Terraform side                      | Template (`.tftpl`) side                       |
| ------------------------------------- | ----------------------------------- | ---------------------------------------------- |
| String / path                         | pass as-is                          | `ARG_FOO='${ARG_FOO}'`                         |
| Boolean                               | `tostring(var.foo)`                 | `ARG_FOO='${ARG_FOO}'`                         |
| Free-form string (may contain quotes) | `base64encode(var.foo)`             | `ARG_FOO=$(echo -n '${ARG_FOO}' \| base64 -d)` |
| Object / list (JSON)                  | `base64encode(jsonencode(var.foo))` | `ARG_FOO=$(echo -n '${ARG_FOO}' \| base64 -d)` |

In `.tftpl` files, write literal bash `$` as `$$` (e.g., `$${HOME}`) so Terraform does not treat them as template interpolations.

```tf
locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_FOO = var.foo
    ARG_BAR = var.bar
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/<namespace>/<module-name>"
  display_name_prefix = "My Module"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
  start_script        = var.start_script # optional; omit if the module does not start a process
}
```

Always expose the `scripts` output as a pass-through so upstream modules can serialize their own `coder_script` resources behind this module's install pipeline:

```tf
output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
```

## Code Style

- Every module MUST have `.tftest.hcl` tests; optional `main.test.ts` for container/script tests
- README frontmatter: `display_name`, `description`, `icon`, `verified: false`, `tags`
- Use semantic versioning; bump version via script when modifying modules
- Docker tests require Linux or Colima/OrbStack (not Docker Desktop)
- Use `tf` (not `hcl`) for code blocks in README; use relative icon paths (e.g., `../../../../.icons/`)
- **Never include parameter listings or input/output variable tables in module or template READMEs.** This includes workspace parameters declared with `coder_parameter`. The registry automatically parses the Terraform source and displays parameters in a dedicated tab on `registry.coder.com`; input/output documentation is also generated from the source. Duplicating these listings in the README is redundant and creates maintenance drift.
- Usage examples (e.g., a `module "..." { }` block) and explanations of parameter behavior are encouraged, but not tables or lists enumerating parameters, inputs, or outputs.
- Script shebangs must be `#!/usr/bin/env bash`, never `#!/bin/bash`. NixOS workspaces have only `/bin/sh`, so the kernel fails the exec before anything runs and the agent reports exit 255 with an empty log — which looks like a broken module, not a missing interpreter.

### Variable and output conventions

Order variable blocks: `description` → `type` → `default` → `validation` → `sensitive`.

```tf
variable "api_key" {
  description = "API key for the service."
  type        = string
  default     = ""
  sensitive   = true
}
```

- Mark variables and outputs that hold secrets or tokens `sensitive = true`.
- Every `output` block must have a `description`.
- Use `count = condition ? 1 : 0` for optional singleton resources. Reserve `for_each` for maps/sets where resource identity matters.

### Extra CLI flags: `additional_args`

When a module lets users pass extra flags to a CLI it runs, name the input `additional_args` and make it a `map(string)` of flag to value. Do not use `extra_args`, `additional_arguments`, `extra_flags`, or a free-form string.

- Each key is passed exactly as written, so the user picks `--long` or `-s`. A non-empty value follows as a separate argument; an empty value passes the flag alone. `{ "--depth" = "1", "--recurse-submodules" = "" }` becomes `--depth 1 --recurse-submodules`.
- Terraform orders map keys alphabetically, and a key can appear only once.
- Validate that every key looks like a flag and no value contains a newline.
- Add a second validation that rejects every flag the module already passes, with a comment beside both the list and the command in the script to keep them in sync.
- Pass the rendered list to the script as `base64encode(join("\n", local.additional_args))`, and read it back one argument per line into an array or `set --`. Never word-split or `eval` it. If the arguments are written into another generated script, quote each one with `printf '%q'`.
- If a module already has an input with another name for this, keep it working and add `additional_args` beside it. Deprecate the old input as described in [Deprecating inputs](#deprecating-inputs), and append its arguments after `additional_args`. (`code-server` and `ttyd` predate this rule: their `additional_args` is a string, and changing its type would break existing templates.)

```tf
variable "additional_args" {
  description = "Additional flags to pass to `tool`, as a map of flag to value. Each flag is passed as written followed by its value as the next argument; an empty value passes the flag alone."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.additional_args : can(regex("^--?[A-Za-z0-9][A-Za-z0-9._-]*$", k)) && !can(regex("\n", v))])
    error_message = "additional_args keys must be flags such as --name or -n, and values must not contain newlines."
  }

  # The module already sets these. Keep this list in sync with the flags in run.sh.
  validation {
    condition     = length(setintersection(keys(var.additional_args), ["--port"])) == 0
    error_message = "additional_args must not set --port; use port instead."
  }
}

locals {
  additional_args = flatten([for k, v in var.additional_args : v == "" ? [k] : [k, v]])
}
```

### Deprecating inputs

Terraform 1.15 added a `deprecated` argument for `variable` blocks: Terraform warns whenever a caller sets the input. Terraform 1.14 and older reject the argument outright (`An argument named "deprecated" is not expected here`), even when the caller never sets the input. Coder bundles Terraform 1.15 from v2.37.0; v2.36 and older bundle 1.14.

- **Major version bump:** set `required_version = ">= 1.15"` in the `terraform` block, and give every deprecated input a `deprecated` argument, including inputs deprecated earlier by description only. Raising the minimum Terraform version is itself a breaking change, so do it only in a major bump, and note it in the PR and README.
- **Minor or patch bump:** do not add `deprecated` or raise `required_version`. Begin the input's description with `Deprecated: use <new_input> instead.` and say so in the README.
- In both cases, keep a deprecated input working until a major version removes it.

`deprecated` takes the warning message, not a boolean: name the replacement input in it (`"Use additional_args instead."`). `deprecated = true` prints the bare message `true`, and `""` prints none. Place `deprecated` after `default`:

```tf
terraform {
  required_version = ">= 1.15"
}

variable "extra_args" {
  description = "Deprecated: use `additional_args` instead."
  type        = list(string)
  default     = []
  deprecated  = "Use additional_args instead."
}
```

### `.tftest.hcl` test commands

- Use `command = plan` only for assertions on **input-derived values** (variables, locals computed from inputs).
- Use `command = apply` for **computed attributes** (resource IDs, anything the provider generates), and for nested blocks of set type (they cannot be indexed with `[0]` under `plan`).

## PR Review Checklist

- Version bumped via `.github/scripts/version-bump.sh` if module changed (patch=bugfix, minor=feature, major=breaking)
- Breaking changes documented: removed inputs, changed defaults, new required variables, raised minimum Terraform version
- Deprecated inputs use the `deprecated` argument and `required_version = ">= 1.15"` on a major bump, or a `Deprecated:` description on a minor or patch bump
- New variables have sensible defaults to maintain backward compatibility
- Tests pass (`bun run check:terraform`, `bun run check:typescript`, or `bun check` for everything); add diagnostic logging for test failures
- README examples updated with new version number; tooltip/behavior changes noted
- Shell scripts handle errors gracefully (use `|| echo "Warning..."` for non-fatal failures)
- No hardcoded values that should be configurable; no absolute URLs (use relative paths)
- If AI-assisted: include model and tool/agent name at footer of PR body (e.g., "Generated with [Amp](thread-url) using Claude")
