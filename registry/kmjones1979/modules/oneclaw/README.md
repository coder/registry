---
display_name: 1Claw
description: Vault-backed secrets and MCP server wiring for 1Claw in Coder workspaces
icon: ../../../../.icons/vault.svg
verified: false
tags: [secrets, mcp, ai]
---

# 1Claw

Give every Coder workspace scoped access to [1Claw](https://1claw.xyz) so AI coding agents can read secrets from an encrypted vault instead of hardcoded credentials. The module supports three provisioning modes — Terraform-native, shell bootstrap, and manual — and merges a `streamable-http` MCP server entry into Cursor and Claude Code config files without overwriting other MCP servers.

Upstream source: [github.com/1clawAI/1claw-coder-workspace-module](https://github.com/1clawAI/1claw-coder-workspace-module).

## Usage

### Terraform-native mode (recommended)

Provisions vault, agent, and access policy at `terraform apply`; cleans up on `terraform destroy`.

```tf
module "oneclaw" {
  source         = "registry.coder.com/kmjones1979/oneclaw/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  master_api_key = var.oneclaw_key
}
```

### Manual mode

Use an existing vault and agent API key from the 1Claw dashboard.

```tf
module "oneclaw" {
  source    = "registry.coder.com/kmjones1979/oneclaw/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  vault_id  = var.oneclaw_vault_id
  api_token = var.oneclaw_agent_key
}
```

### Shell bootstrap mode

Creates vault and agent on the first workspace boot, then caches credentials for subsequent starts.

```tf
module "oneclaw" {
  source        = "registry.coder.com/kmjones1979/oneclaw/coder"
  version       = "1.0.0"
  agent_id      = coder_agent.main.id
  human_api_key = var.oneclaw_human_key
}
```

> [!NOTE]
> **Terraform-native mode** runs a `local-exec` provisioner on the machine executing Terraform. It needs network access to the 1Claw API, `curl`, and `python3`.

> [!TIP]
> Combine this module with other registry modules (e.g. Cursor or Claude Code). The MCP setup script merges into existing `mcp.json` files instead of replacing them.
