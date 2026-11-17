---
display_name: AI Gateway Token
description: Workaround that creates a narrowly scoped Coder API token for AI Gateway, so agents do not get the owner's full-access session token.
icon: ../../../../.icons/coder.svg
verified: false
tags: [helper, ai, ai-gateway, security]
---

# AI Gateway Token

Create a Coder API token with narrow scopes for [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway), and pass it to an agent module instead of the workspace owner's session token.

> [!WARNING]
> This module is a temporary workaround, not the long-term fix.
> AI Gateway has no scope of its own and doesn't check token scopes, and Coder has no gateway-only workspace credential yet.
> The token this module creates isn't a workspace session token, so AI Gateway loses workspace attribution for these requests.
> Use it only when keeping the full-access token away from agents matters more than per-workspace usage data and budgets.
> Once Coder provides a gateway-only workspace token, switch to it and remove this module.

```tf
module "ai_gateway_token" {
  source  = "registry.coder.com/coder-labs/ai-gateway-token/coder"
  version = "1.0.0"
}

module "claude-code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = "5.6.0"
  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
  ai_gateway_token  = module.ai_gateway_token.token
}
```

## Why

`data.coder_workspace_owner.me.session_token` has the owner's full access to the Coder API.
An agent that can read it can use it to reach the owner's other workspaces, create workspaces from any template the owner can use, and create more tokens.
This holds even when the agent runs in a network sandbox, because AI Gateway is served from the same host as the rest of the Coder API, so a sandbox that lets the agent reach AI Gateway usually lets it reach the whole API.

This module uses the session token only in the provisioner, during the build, to create a token with the `user:read_personal` scope.
Only that token is put in the workspace.
AI Gateway accepts it, and the rest of the Coder API rejects it for most requests.

## How it works

- The token is created at apply time on each workspace start. A plan creates nothing.
- Prebuilds get an empty token. The claim build creates a token for the new owner.
- If the Coder API does not return `201`, the build fails. The module never falls back to the owner's session token.
- The token is not revoked when the workspace stops, because Coder deletes the session token before a stop build runs.
  It expires after `lifetime_hours`, or after the deployment's default token lifetime when `lifetime_hours` is `0`.
  Each start creates a new token named `ai-gateway-<workspace-id-prefix>-<timestamp>`.

## Requirements

- The provisioner must reach the Coder access URL over HTTPS.
- The `hashicorp/http` provider. Air-gapped deployments must mirror it.
- The owner must be allowed to create API tokens with the requested lifetime.

## Limitations

- AI Gateway does not attribute requests made with this token to the workspace, because it derives the workspace from the name of the workspace session token.
  Requests are still attributed to the owner.
  In a deployment with more than one organization, a request takes the organization of the owner's effective group instead of the workspace's organization.
- A workspace that runs longer than the token lifetime loses AI Gateway access until it restarts.
  Set `lifetime_hours` to cover the longest expected run.
- The token is stored in the Terraform state, as the owner's session token already is.
