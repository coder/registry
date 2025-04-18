---
display_name: Hashicorp Vault Integration (JWT)
description: Authenticates with Vault using a JWT from Coder's OIDC provider
icon: ../../../../.icons/vault.svg
maintainer_github: coder
partner_github: hashicorp
verified: true
tags: [helper, integration, vault, jwt, oidc]
---

# Hashicorp Vault Integration (JWT)

This module lets you authenticate with [Hashicorp Vault](https://www.vaultproject.io/) in your Coder workspaces by reusing the [OIDC](https://coder.com/docs/admin/users/oidc-auth) access token from Coder's OIDC authentication method. This requires configuring the Vault [JWT/OIDC](https://developer.hashicorp.com/vault/docs/auth/jwt#configuration) auth method.

```tf
module "vault" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vault-jwt/coder"
  version        = "1.0.20"
  agent_id       = coder_agent.example.id
  vault_addr     = "https://vault.example.com"
  vault_jwt_role = "coder" # The Vault role to use for authentication
}
```

Then you can use the Vault CLI in your workspaces to fetch secrets from Vault:

```shell
vault kv get -namespace=coder -mount=secrets coder
```

or using the Vault API:

```shell
curl -H "X-Vault-Token: ${VAULT_TOKEN}" -X GET "${VAULT_ADDR}/v1/coder/secrets/data/coder"
```

## Examples

### Configure Vault integration with a non standard auth path (default is "jwt")

```tf
module "vault" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/modules/vault-jwt/coder"
  version             = "1.0.20"
  agent_id            = coder_agent.example.id
  vault_addr          = "https://vault.example.com"
  vault_jwt_auth_path = "oidc"
  vault_jwt_role      = "coder" # The Vault role to use for authentication
}
```

### Map workspace owner's group to a Vault role

```tf
data "coder_workspace_owner" "me" {}

module "vault" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vault-jwt/coder"
  version        = "1.0.20"
  agent_id       = coder_agent.example.id
  vault_addr     = "https://vault.example.com"
  vault_jwt_role = data.coder_workspace_owner.me.groups[0]
}
```

### Install a specific version of the Vault CLI

```tf
module "vault" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/modules/vault-jwt/coder"
  version           = "1.0.20"
  agent_id          = coder_agent.example.id
  vault_addr        = "https://vault.example.com"
  vault_jwt_role    = "coder" # The Vault role to use for authentication
  vault_cli_version = "1.17.5"
}
```
