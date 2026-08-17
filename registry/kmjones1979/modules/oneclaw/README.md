---
display_name: 1Claw
description: Vault-backed secrets and MCP server wiring for 1Claw in Coder workspaces
icon: ../../../../.icons/1claw.png
verified: false
tags: [secrets, mcp, ai]
---

# 1Claw

Give every Coder workspace scoped access to [1Claw](https://1claw.xyz) so AI coding agents can read secrets from an encrypted vault instead of hardcoded credentials. The module merges a hosted MCP server entry ([`https://mcp.1claw.xyz/mcp`](https://docs.1claw.xyz/docs/mcp/setup), HTTP streaming transport) into Cursor and Claude Code config files without overwriting other MCP servers.

For AI-oriented product documentation, see [llms.txt](https://1claw.xyz/llms.txt) and the [1Claw docs](https://docs.1claw.xyz).

```tf
module "oneclaw" {
  source        = "registry.coder.com/kmjones1979/oneclaw/coder"
  version       = "1.0.0"
  agent_id      = coder_agent.main.id
  human_api_key = var.oneclaw_human_key
}
```

Upstream source: [github.com/1clawAI/1claw-coder-workspace-module](https://github.com/1clawAI/1claw-coder-workspace-module).

Runtime state, scripts, and logs live under `$HOME/.coder-modules/kmjones1979/oneclaw/`.

## Usage

### Bootstrap mode (recommended)

Creates a vault, agent, and access policy on the first workspace boot using a human `1ck_` API key, then caches credentials in `$HOME/.coder-modules/kmjones1979/oneclaw/bootstrap.json` for subsequent starts. This is the configuration shown at the top of this README.

#### Post-bootstrap cleanup (recommended)

The `1ck_` human key is a privileged credential that can create and destroy vaults in your 1Claw account. It is only needed the first time the workspace boots. After the initial bootstrap succeeds:

1. Clear the variable in your Terraform:

   ```tf
   module "oneclaw" {
     source        = "registry.coder.com/kmjones1979/oneclaw/coder"
     version       = "1.0.0"
     agent_id      = coder_agent.main.id
     human_api_key = "" # scrubbed after first bootstrap
   }
   ```

2. Re-apply the template. On the next workspace start, the script loads credentials from `$HOME/.coder-modules/kmjones1979/oneclaw/bootstrap.json` and no longer references the human key. The workspace continues to work with the scoped `ocv_` agent key only.

> [!NOTE]
> Workspaces that previously bootstrapped to `~/.1claw/bootstrap.json` are migrated automatically on the next start.

### Manual mode

Pre-provision the vault and agent out-of-band and pass only the scoped `ocv_` agent key. Recommended for production and for threat models that include untrusted code running inside the workspace.

```tf
module "oneclaw" {
  source    = "registry.coder.com/kmjones1979/oneclaw/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  vault_id  = var.oneclaw_vault_id
  api_token = var.oneclaw_agent_key
}
```

## Security notes

The module is written so that the `1ck_` human bootstrap key leaves no persistent trace in the workspace:

- The `ocv_` agent key exposed to the AI is scoped to a single vault and a single secret-path policy. That defines the blast radius of anything the AI does.
- The `1ck_` human key is injected into the bootstrap script as a sensitive `coder_env` variable (`_ONECLAW_HUMAN_API_KEY`), **never** templated into the script body. Because of this, it does **not** appear in `/tmp/coder-agent.log` (which records the rendered script) or in the Terraform state file's `coder_script` resource. The rendered script only contains the literal reference `HUMAN_KEY="${_ONECLAW_HUMAN_API_KEY:-}"`.
- During bootstrap, the human key is sent to the 1Claw API via `curl --data-binary @-` from stdin, so it never appears in process argv (`ps aux` / `/proc/<pid>/cmdline`).
- The key is scrubbed from shell variables (`unset HUMAN_KEY` / `unset _ONECLAW_HUMAN_API_KEY`) immediately after authentication, so downstream processes started by the script do not inherit it.
- The key is **never** written to `bootstrap.json`, `~/.cursor/mcp.json`, `~/.config/claude/mcp.json`, or any other on-disk file. Only the scoped `ocv_` agent key and the vault id are persisted under `$HOME/.coder-modules/kmjones1979/oneclaw/`.
- For highest assurance, use manual mode with a pre-provisioned `ocv_` key so the `1ck_` key never reaches the workspace at all.

## Requirements

Bootstrap mode runs inside the workspace and requires `curl` and `python3` in the container image.
