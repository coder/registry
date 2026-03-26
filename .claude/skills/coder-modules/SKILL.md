---
name: coder-modules
description: Creates and updates Coder Registry modules with proper scaffolding, Terraform testing, README frontmatter, and version management
---

# Coder Modules

Coder Registry modules are reusable Terraform components that live under `registry/<namespace>/modules/<name>/` and are consumed by templates via `module` blocks.

## Before You Start

Before writing or modifying any code:

1. **Understand the request.** What tool, integration, or functionality is the module providing? What Coder resources does it need (`coder_script`, `coder_app`, `coder_env`, etc.)? Read the official documentation for the target tool or integration (installation steps, CLI flags, config files, environment variables, ports) so you can implement the module properly without guessing.
2. **Research existing modules.** Search the registry for similar modules. Read their `main.tf` to understand patterns, variable conventions, and how they solve similar problems. Avoid duplicating existing functionality.
3. **Check the Coder provider docs.** Verify that the resources and attributes you plan to use exist in the provider version you're targeting. Use the version-specific docs URL if needed.
4. **Clarify before building.** If the request is ambiguous (e.g. unclear which Coder resource to use, whether a `coder_app` vs `coder_script` is appropriate, what variables to expose, or which namespace to use), ask for clarification rather than guessing. Never assume a namespace; always confirm with the user.
5. **Plan the structure.** Decide on script organization (root `run.sh`, `scripts/` directory, or inline), what variables to expose, and what tests to write.

## Documentation References

### Coder

- Coder docs (latest): <https://coder.com/docs>
- Version-specific Coder docs: `https://coder.com/docs/@v{MAJOR}.{MINOR}.{PATCH}` (e.g. <https://coder.com/docs/@v2.31.5>)
- Coder Registry: <https://registry.coder.com>

### Coder Terraform provider

- Provider docs (latest): <https://registry.terraform.io/providers/coder/coder/latest/docs>
- Version-specific provider docs: replace `latest` with a version number (e.g. <https://registry.terraform.io/providers/coder/coder/2.13.1/docs>)

Resources:

| Resource         | Docs                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| `coder_app`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/app>      |
| `coder_script`   | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script>   |
| `coder_env`      | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/env>      |
| `coder_metadata` | <https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata> |

Data sources:

| Data Source             | Docs                                                                                           |
| ----------------------- | ---------------------------------------------------------------------------------------------- |
| `coder_parameter`       | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/parameter>       |
| `coder_workspace`       | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace>       |
| `coder_workspace_owner` | <https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace_owner> |

## Scaffolding a New Module

Only use this when creating a brand new module that does not yet exist. When updating an existing module, edit its files directly.

From repo root:

```bash
./scripts/new_module.sh namespace/module-name
```

Names must be lowercase alphanumeric with hyphens or underscores (e.g. `coder/my-tool`).

Creates `registry/<namespace>/modules/<module-name>/` with:

- `main.tf`: Terraform config with coder provider
- `README.md`: frontmatter and usage examples
- `MODULE_NAME.tftest.hcl`: Terraform native tests
- `run.sh`: install/start-up script template

If the namespace is new, the script also creates `registry/<namespace>/` with a README. New namespaces additionally need:

- `registry/<namespace>/.images/avatar.svg` (or `.png`): square image, 400x400px minimum
- The namespace README `avatar` field pointing to `./.images/avatar.svg`

The generated namespace README contains placeholder fields (`display_name`, `bio`, `status`, `github`, `avatar`, etc.) that the user must fill out. The `status` field is required and must be `official`, `partner`, or `community` (typically `community` for new contributors). After completing the module, inform the user that the namespace README needs to be updated with their information.

## main.tf

```tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

resource "coder_script" "my_tool" {
  agent_id     = var.agent_id
  display_name = "My Tool"
  icon         = local.icon_url
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "my_tool" {
  agent_id     = var.agent_id
  slug         = "my-tool"
  display_name = "My Tool"
  url          = "http://localhost:${var.port}"
  icon         = local.icon_url
  subdomain    = false
  share        = "owner"
  order        = var.order

  healthcheck {
    url       = "http://localhost:${var.port}/healthz"
    interval  = 5
    threshold = 6
  }
}
```

Key patterns:

- Provider version constraints must reflect actual functionality requirements. Only raise the minimum `coder` provider version (e.g. `>= 2.5` to `>= 2.8`) when the module uses a resource, attribute, or behavior introduced in that version; check the provider changelog to confirm.
- Variable names MUST be `snake_case` (no hyphens; validation rejects them)
- New variables must have sensible defaults for backward compatibility
- Common variable: `agent_id` (string, required, no default)
- Common variable: `order` (number, default `null`, controls UI position)
- Use `locals {}` for computed values: URL normalization, base64 encoding, `file()` script content, config assembly
- Modules can consume other registry modules via `module` blocks (e.g. `cursor` uses `vscode-desktop-core`, CLI wrappers use `agentapi`). Before consuming a module, read its `main.tf` and `README.md` to understand the full interface: accepted variables, outputs, prerequisites, and runtime requirements. If you are inside the registry repo, read these files directly. Otherwise, read the module's page at `https://registry.coder.com/modules/<namespace>/<module-name>` which includes the full source, README, and variable definitions. Never pass arguments without confirming they exist.
- `coder_script` icons use the `/icon/<name>.svg` format. The `display_name` is typically the product name (e.g. "code-server", "Git Clone", "File Browser").
- Do not add comments that narrate what the code does or label sections. Only comment when explaining something non-obvious (e.g. why a workaround exists, a subtle constraint, or an unusual design choice).

## README.md

Required YAML frontmatter:

```yaml
---
display_name: My Tool
description: Short description of what this module does
icon: ../../../../.icons/tool.svg
verified: false
tags: [helper, ide]
---
```

Content rules:

- Single H1 heading matching `display_name`, directly below frontmatter
- When increasing header levels, increment by one each time (h1 -> h2 -> h3, not h1 -> h3)
- Usage snippet with `registry.coder.com/<ns>/<module>/coder` and pinned `version`
- Code fences labeled `tf` (NOT `hcl`)
- Relative icon paths (e.g. `../../../../.icons/`)
- **Do NOT include tables or lists that enumerate variables, parameters, or outputs.** The registry generates variable and output documentation automatically from the Terraform source. Describe what the module does and how to use it in prose, not by listing every configurable field.
- Usage examples are encouraged
- Use [GFM alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts) for callouts: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`

```tf
module "my_tool" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/namespace/my-tool/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Icons

Modules reference icons in two places with different path systems:

- **README frontmatter** `icon:` uses a relative path to the repo's `.icons/` directory (e.g. `../../../../.icons/my-tool.svg`). Displayed on the registry website.
- **`coder_script` / `coder_app`** `icon =` uses an absolute `/icon/<name>.svg` path served by the Coder deployment from `site/static/icon/` in the `coder/coder` repo. Displayed in the workspace agent bar.

Workflow:

1. **Check what exists.** List the `.icons/` directory at the repo root for available SVGs. For `/icon/` paths, look at what similar modules already use.
2. **Use existing icons when they fit.** If the tool already has an icon in `.icons/` and `/icon/`, use those.
3. **When an icon doesn't exist,** reference the expected path anyway (e.g. `../../../../.icons/my-tool.svg` and `/icon/my-tool.svg`) so the structure is correct. Try to source the official SVG from the tool's branding page or repository. If you can obtain it, add it to `.icons/` in this repo.
4. **Don't substitute a generic icon.** If the tool has its own brand identity, use the correct name even if the file doesn't exist yet. Don't fall back to generic icons like `coder.svg` or `terminal.svg`.
5. **Notify the user.** After completing the module, inform the user in your response if any icons were referenced but not found. Note that missing icons need to be sourced and added to both this repo's `.icons/` directory and the `coder/coder` repo at `site/static/icon/`.

## Scripts

Modules use three patterns for shell logic, depending on complexity:

### Root `run.sh` + `templatefile()` (simple modules)

A single `run.sh` at the module root, loaded via `templatefile()` to inject Terraform variables. Used by `code-server`, `vscode-web`, `git-clone`, `dotfiles`, `filebrowser`.

```tf
resource "coder_script" "my_tool" {
  agent_id     = var.agent_id
  display_name = "My Tool"
  icon         = "/icon/my-tool.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
  })
  run_on_start = true
}
```

Use `$${VAR}` (double dollar) in the shell script for Terraform `templatefile` escaping.

If a script sources external files (`$HOME/.bashrc`, `/etc/bashrc`, `/etc/os-release`), the `source` statement must come before `set -u`; CI enforces this ordering.

### `scripts/` directory + `file()` (complex modules)

Separate `scripts/install.sh` and `scripts/start.sh` loaded via `file()` into `locals`, then passed to a child module or encoded inline. Used by `coder/claude-code`, `coder-labs/copilot`, `coder-labs/codex`, `coder-labs/cursor-cli`, `coder/amazon-q` for example.

```tf
locals {
  install_script = file("${path.module}/scripts/install.sh")
  start_script   = file("${path.module}/scripts/start.sh")
}
```

Use `file()` when scripts don't need Terraform variable interpolation. For config templates, use a `templates/` directory with `templatefile()` (e.g. `coder/amazon-q/templates/agent-config.json.tpl`).

### Inline heredoc (minimal modules)

For trivial logic, embed the script directly in the `coder_script` resource. Used by `cursor`, `zed`.

Modules that use a `scripts/` directory often also have a `testdata/` directory containing mock scripts for testing (e.g. `testdata/my-tool-mock.sh`).

## Testing

### .tftest.hcl (Required)

Every module must have Terraform native tests. The file can be named `main.tftest.hcl` or `<module-name>.tftest.hcl`. Use `command = plan` for most cases:

```hcl
run "plan_with_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = var.agent_id == "test-agent-id"
    error_message = "agent_id should be set"
  }
}

run "custom_port" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    port     = 8080
  }

  assert {
    condition     = resource.coder_app.my_tool.url == "http://localhost:8080"
    error_message = "App URL should use configured port"
  }
}
```

Advanced patterns:

- `override_data` to mock data sources like `coder_workspace` and `coder_workspace_owner`
- `command = apply` when testing outputs or computed values
- `expect_failures` to test validation rules
- `regexall()` / `startswith()` / `endswith()` for string assertions
- Assert on `coder_env`, `coder_script`, `coder_app` resource attributes

```hcl
run "with_mocked_workspace" {
  command = apply

  variables {
    agent_id = "foo"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      name = "test-workspace"
    }
  }

  assert {
    condition     = output.url == "expected-value"
    error_message = "URL should match expected format"
  }
}

run "validation_rejects_conflict" {
  command = plan

  variables {
    agent_id       = "test"
    option_a       = true
    option_b       = true
  }

  expect_failures = [
    var.option_a,
  ]
}
```

### main.test.ts (Optional)

For more complex testing (Docker containers, script execution, HTTP mocking).
Import from `~test` (mapped to `test/test.ts` via `tsconfig.json`):

```typescript
import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  findResourceInstance,
} from "~test";

describe("my-tool", () => {
  it("should init successfully", async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("should apply with defaults", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const app = findResourceInstance(state, "coder_app");
    expect(app.slug).toBe("my-tool");
    expect(app.display_name).toBe("My Tool");
  });
});
```

### Test utility API (`~test`)

**Terraform helpers:**

- `runTerraformInit(dir)`: runs `terraform init`.
- `runTerraformApply(dir, vars, customEnv?)`: runs `terraform apply` with a random state file and returns `TerraformState`. Variables are passed as `TF_VAR_*`. Safe to run in parallel. `TerraformState` has `outputs: Record<string, TerraformOutput>` and `resources: TerraformStateResource[]`.
- `testRequiredVariables(dir, vars)`: auto-generates test cases (one success with all vars, plus one per var verifying apply fails without it). Pass `{}` if there are no required vars.
- `findResourceInstance(state, type, name?)`: finds the first resource instance by type. Throws if not found. Optionally filters by name.

**Docker helpers** (require `--network host`, Linux/Colima/OrbStack):

- `runContainer(image, init?)`: starts a detached container and returns its ID. Labeled `modules-test=true` for auto-cleanup.
- `removeContainer(id)`: force-removes a container.
- `execContainer(id, cmd[], args?[])`: runs a command in a container and returns `{ exitCode, stdout, stderr }`.
- `executeScriptInContainer(state, image, shell?, before?)`: finds `coder_script` in state, runs it in a container, and returns `{ exitCode, stdout: string[], stderr: string[] }`.

**File helpers:**

- `writeCoder(id, script)`: writes a mock `coder` CLI to `/usr/bin/coder` in the container.
- `writeFileContainer(id, path, content, { user? })`: writes a file to the container via base64.
- `readFileContainer(id, path)`: reads a file from the container as root.

**HTTP helpers:**

- `createJSONResponse(obj, statusCode?)`: creates a `Response` with a JSON body (defaults to 200).

Cleanup of `*.tfstate` files and `modules-test` Docker containers is handled automatically by `setup.ts` (preloaded via `bunfig.toml`).

## Commands

| Task             | Command                                                 | Scope      |
| ---------------- | ------------------------------------------------------- | ---------- |
| Format all       | `bun run fmt`                                           | Repo       |
| Terraform tests  | `bun run tftest`                                        | Repo       |
| TypeScript tests | `bun run tstest`                                        | Repo       |
| Single TF test   | `terraform init -upgrade && terraform test -verbose`    | Module dir |
| Single TS test   | `bun test main.test.ts`                                 | Module dir |
| Validate         | `./scripts/terraform_validate.sh`                       | Repo       |
| ShellCheck       | `bun run shellcheck`                                    | Repo       |
| README validate  | `go build ./cmd/readmevalidation && ./readmevalidation` | Repo       |
| Version bump     | `.github/scripts/version-bump.sh patch\|minor\|major`   | Repo       |

## Version Management

Bump version via `.github/scripts/version-bump.sh` when modifying modules:

- `patch`: bugfixes
- `minor`: new features, new variables with defaults
- `major`: breaking changes (removed inputs, changed defaults, new required variables)

The script automatically updates `version` references in README usage examples.

## Final Checks

Before considering the work complete, verify:

- Tests pass: `bun run tftest` and `bun run tstest`
- `bun run fmt` has been run
- `bun run shellcheck` passes if the module includes shell scripts
- `go build ./cmd/readmevalidation && ./readmevalidation` passes (validates frontmatter, icon paths, body structure, GFM alerts)
- New variables have sensible defaults for backward compatibility
- Breaking changes are documented if any inputs were removed, defaults changed, or new required variables added
- Shell scripts handle errors gracefully (`|| echo "Warning..."` for non-fatal failures)
- No hardcoded values that should be configurable via variables
- Asset and icon paths in frontmatter and Terraform must be relative (e.g. `../../../../.icons/`), not absolute. External hyperlinks to docs or other websites are fine.
