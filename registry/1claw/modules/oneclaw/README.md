---
display_name: 1Claw
description: Vault-backed secrets and MCP server wiring for 1Claw in Coder workspaces
icon: ../../../../.icons/vault.svg
verified: false
tags: [secrets, mcp, ai]
---

# 1Claw

Give every workspace scoped access to 1Claw so AI tools can use secrets from an encrypted vault instead of hardcoded keys or checked-in `.env` files. The module can create vault and agent resources automatically (Terraform-native mode), bootstrap them on first workspace start (shell mode), or use credentials you already manage (manual mode). It merges a `streamable-http` MCP server entry into Cursor and Claude Code config files without wiping other MCP servers.

Upstream source and issue tracker: [github.com/1clawAI/1claw-coder-workspace-module](https://github.com/1clawAI/1claw-coder-workspace-module).

> [!NOTE]
> **Terraform-native mode** runs a `local-exec` provisioner on the machine executing Terraform (often your Coder provisioner). It needs network access to `base_url`, `curl`, and `python3`. A state file `.provision-state.json` is written next to the module; keep that directory out of version control (the module ships a `.gitignore` entry).

> [!TIP]
> Combine this module with other registry modules (for example Cursor or Claude Code). The MCP setup script merges into existing `mcp.json` files instead of replacing them.

## Usage

```tf
module "oneclaw" {
  source   = "registry.coder.com/1claw/oneclaw/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  # Terraform-native (recommended for ephemeral workspaces): set master_api_key (1ck_...).
  master_api_key = var.oneclaw_key
}
```

Manual mode with an existing vault and agent API key:

```tf
module "oneclaw" {
  source    = "registry.coder.com/1claw/oneclaw/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  vault_id  = var.oneclaw_vault_id
  api_token = var.oneclaw_agent_key
}
```

Shell bootstrap (human API key on first boot only):

```tf
module "oneclaw" {
  source               = "registry.coder.com/1claw/oneclaw/coder"
  version              = "1.0.0"
  agent_id             = coder_agent.main.id
  human_api_key        = var.oneclaw_human_key
  bootstrap_vault_name = "my-team-vault"
}
```

## License

The upstream project is licensed under Apache-2.0.
