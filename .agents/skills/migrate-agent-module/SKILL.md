---
name: migrate-agent-module
description: Migrate a Coder AI agent module (Copilot, Claude Code, Codex, Cursor CLI, etc.) off AgentAPI/Coder Tasks to an install-only v1 module that the user launches with their own coder_app. Captures the config/precedence, auth, MCP, managed-settings, and testing patterns learned from the Copilot v1 migration.
---

# Migrate Agent Module (AgentAPI/Tasks -> install-only v1)

Use this when converting a CLI-agent module that currently embeds `module "agentapi"` and Coder Tasks (web app, task reporting, initial prompt) into a **v1 install-only module**: the module installs and configures the tool, and the workspace author launches it themselves with a `coder_app`. This is the pattern used by `coder/claude-code`, `coder-labs/codex`, and `coder-labs/copilot`.

Read [coder-modules](../coder-modules/SKILL.md) first for the base module conventions (scaffolding, README frontmatter, testing helpers, versioning). This skill only covers what is specific to the AgentAPI -> install-only migration.

## Golden rule: research the target tool before editing

Every agent CLI stores config differently and the schemas change. Do not assume. Before writing code, read the tool's own docs and verify against a real install:

- Config file locations, exact key names, and **casing** (e.g. Copilot uses `trustedFolders`, camelCase, not `trusted_folders`).
- Settings **precedence** (managed/policy vs user vs env vs CLI flags).
- Which keys are valid in each file (e.g. Copilot managed settings only accept a fixed policy key set; `banner`/`theme` are user `settings.json`, not `config.json`).
- Authentication env vars and their precedence.
- Whether a CLI subcommand you plan to call actually exists. Run `<tool> --help` / `<tool> <cmd> --help`. Example bug caught in the Copilot migration: `copilot config model ...` is **not a command** (`config` is only a help topic); the model is set via the `COPILOT_MODEL` env var.
- MCP add/merge semantics (does the native `mcp add` overwrite or error on duplicate names?).

When docs and third-party sources conflict, trust the official docs and confirm against the installed binary. Cite the doc URL in variable descriptions.

## What to remove (AgentAPI / Tasks surface)

Delete the `module "agentapi"` block and every input/resource that only existed to feed it:

- Web/app inputs: `order`, `group`, `web_app_display_name`, `cli_app`, `cli_app_display_name`, `subdomain`.
- AgentAPI inputs: `install_agentapi`, `agentapi_version`.
- Tasks inputs: `report_tasks`, `ai_prompt`, `system_prompt`, `resume_session`, and any `task_app_id`.
- The task-reporting MCP server injection (the "coder" MCP wrapper that ran `coder exp mcp server`).
- `scripts/start.sh` (there is no launch step anymore) and the old `<module>.tftest.hcl`.

## What to add / keep

- `module "coder_utils"` (`registry.coder.com/coder/coder-utils/coder`) to run the install pipeline and expose the ordered `scripts` output. It takes `install_script`, `pre_install_script`, `post_install_script`, `module_directory`, `display_name_prefix`, `icon`, `agent_id`.
- An install-only `scripts/install.sh.tftpl` rendered via `templatefile()` with base64-encoded args.
- Keep `workdir` (optional, `default = null`): create it if missing and auto-trust it (the tool's equivalent of accepting the trust prompt).
- Keep pre/post install script passthrough.
- A `scripts` output for downstream `coder_script` serialization via `coder exp sync`.

See `reference.md` in this folder for the concrete `coder_utils` block, install-script skeleton, and jq merge snippets.

## Install script (`scripts/install.sh.tftpl`)

- Shebang `#!/usr/bin/env bash` (repo convention), `set -euo pipefail`.
- Prefer the tool's **official installer** over npm/node. Download to a temp file, validate with `bash -n`, then execute. Use these curl flags:
  ```sh
  curl --fail --silent --show-error --location \
    --retry 2 --retry-delay 1 --retry-all-errors \
    --connect-timeout 10 --max-time 300
  ```
  On download or validation failure, print an explicit message and return non-zero. Run cleanup in a subshell-scoped `trap`.
- Do not add Node.js/npm install logic unless the tool genuinely requires it; the official installers ship self-contained binaries. (Consequence to document: MCP servers whose `command` is `npx`/`uv` will fail with ENOENT unless that runtime is installed separately or an absolute path is used.)
- Pass version straight through (e.g. `VERSION="$ARG_VERSION"`); the official installer normalizes `latest`/tags. Do not reimplement normalization.
- Put the binary on PATH: link into `CODER_SCRIPT_BIN_DIR` when set, and append the bin dir to shell profiles (`.profile`, `.bashrc`, `.zshrc`, fish) because the coder scripts run non-interactively.
- Only create the workdir when set and missing (`mkdir -p`).

## Configuration ownership model

Follow "clear ownership like codex/claude-code":

- The module owns only the keys it writes; **preserve unrelated on-disk state** (authentication, installed plugins, user-picked values).
- Before a jq merge, validate the existing file is valid JSON (`jq empty`); config files may be JSONC. Fall back to `{}` if invalid so the script never crashes. Require `jq` and fail with a clear message if missing.
- Union list-like keys (e.g. trusted folders) rather than replacing them.
- Prefer a **policy/managed-settings input** over a generic "dump arbitrary JSON into the user settings file" input, mirroring claude-code's `managed_settings`:
  - `variable "managed_settings" { type = any, default = null }`.
  - Written verbatim to the tool's managed-settings file (Copilot: `/etc/github-copilot/managed-settings.json`; Claude Code: `/etc/claude-code/managed-settings.d/10-coder.json`).
  - Write as **root** (`sudo tee`, `sudo chmod 0644`); these files are rejected if world-writable, symlinked, or not root-owned. Validate JSON first; skip with a warning if invalid.
- workdir trust: write only the trust key/array and preserve everything else in that file.

## Authentication

- Use one tool-specific token env var when the tool has one, instead of exporting several. Copilot precedence is `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN`, so setting `COPILOT_GITHUB_TOKEN` alone is enough for the agent. Only export extra vars if you deliberately want to authenticate other workspace tooling (`gh`, git); document that choice.
- In README examples, fetch the token with the `coder_external_auth` data source and pass `.access_token` to the module (`github_token = data.coder_external_auth.github.access_token`) rather than shelling out to `coder external-auth access-token` inside the `coder_app` command.

## Model selection

- Set the model via the documented env var (Copilot: `COPILOT_MODEL`) using a `coder_env`. Confirm the env var still exists in the current docs.
- Default the model variable to `""` (let the tool pick its own default); gate the `coder_env` on `!= ""`. Mirrors claude-code's `model` variable.
- Do not call unverified persistence subcommands.

## MCP

- Write MCP servers to the tool's user-level MCP file (Copilot: `~/.copilot/mcp-config.json`) via jq.
- Match the tool's native duplicate-name behavior. Copilot/Claude Code `mcp add` is **not** an upsert: it errors on an existing name and keeps the current one. So the merge should let **existing on-disk servers win** on duplicate names and only add new names: `.mcpServers = ($custom + (.mcpServers // {}))` (right operand wins in jq `+`).

## AI Gateway / proxy

- If the pre-migration module had AI Bridge Proxy support, keep it renamed to the current product name (`ai_gateway`), matching whatever `main` already renamed. Keep both env vars: `HTTPS_PROXY` (routes traffic) and `NODE_EXTRA_CA_CERTS` (makes Node trust the gateway's intercepting CA) — they serve different purposes.
- Without a start script the env vars are set at the agent level (workspace-wide) instead of process-scoped. Decide whether to document that difference; keep validations that require the auth URL and cert path when enabled.

## README

- Add a `> [!WARNING]` that v1 is a major refactor dropping Coder Tasks/AgentAPI and that the user now launches the tool with their own `coder_app`.
- Provide a launcher example: `coder_external_auth` data source -> module (`github_token`) -> `coder_app` whose command `cd`s to the workdir and `exec`s the CLI.
- Keep it DRY: no variable/output tables (the registry generates those). Use `tf` code fences, GFM alerts, relative icon paths, pinned `version`, and `#!/usr/bin/env bash` in shell snippets.
- Remove Tasks/web-app examples and any notes that no longer apply.

## Tests

- Replace the old `<module>.tftest.hcl` with `main.tftest.hcl` (plan-level): defaults, token env var name/value, model env created only when non-empty, validation `expect_failures`, and the `scripts` output ordering.
- Add container-based `main.test.ts` modeled on codex/claude-code: render the module, run the `coder_utils` scripts inside `codercom/enterprise-node:latest`, mock `/usr/bin/coder` (and the agent binary) so `coder exp sync` and validation succeed, then assert on the written files. `sudo` works in that image, so managed-settings-to-`/etc` writes are testable (`cat` the file; assert the "Wrote ... managed settings" log line and an absence test when unset).
- Import helpers from `../../../coder/modules/agentapi/test-util` (`extractCoderEnvVars`, `writeExecutable`) and `~test`.

## Process and conventions

- Commit as `type(scope): message` where the scope is a real path containing every changed file.
- Run before hand-off: `bun x prettier --write <module dir>`, `terraform fmt`, `terraform validate`, `terraform test`, `bun test main.test.ts`.
- Use concise, substantive comments only. No section-divider banners, no narration of what the code does, no "mirrors claude-code" storytelling.
- End files with a newline; use `/usr/bin/env bash` shebangs.
- Never bypass git hooks; do not commit to protected branches; use a feature branch.

## Migration checklist

1. Read the tool's config/auth/MCP/model docs and verify subcommands against `--help`.
2. Remove the AgentAPI/Tasks surface (variables, `module "agentapi"`, `start.sh`, old tftest, task MCP).
3. Add `coder_utils` + `install.sh.tftpl` using the official installer.
4. Implement config ownership: `managed_settings` (root-written policy), workdir trust, MCP merge with correct duplicate semantics.
5. Auth via a single documented token env var; model via the documented env var, default `""`.
6. Port AI Gateway/proxy if present (both proxy env vars, validations).
7. Rewrite README (WARNING, coder_external_auth launcher, DRY).
8. Rewrite tests (`main.tftest.hcl` + container `main.test.ts`).
9. Format, validate, run both test suites.
10. Bump version as a **major** (removed inputs, changed defaults, new required behavior) per [coder-modules](../coder-modules/SKILL.md) versioning.
