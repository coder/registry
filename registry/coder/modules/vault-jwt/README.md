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

This module lets you authenticate with [Hashicorp Vault](https://www.vaultproject.io/) in your Coder workspaces by reusing the [OIDC](https://coder.com/docs/admin/users/oidc-auth) access token from Coder's OIDC authentication method or another source of jwt token. This requires configuring the Vault [JWT/OIDC](https://developer.hashicorp.com/vault/docs/auth/jwt#configuration) auth method.

```tf
module "vault" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/vault-jwt/coder"
  version         = "1.1.0"
  agent_id        = coder_agent.example.id
  vault_addr      = "https://vault.example.com"
  vault_jwt_role  = "coder"                # The Vault role to use for authentication
  vault_jwt_token = "eyJhbGciOiJIUzI1N..." # optional, if not present, defaults to user's oidc authentication token
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
  source              = "registry.coder.com/coder/vault-jwt/coder"
  version             = "1.0.31"
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
  source         = "registry.coder.com/coder/vault-jwt/coder"
  version        = "1.0.31"
  agent_id       = coder_agent.example.id
  vault_addr     = "https://vault.example.com"
  vault_jwt_role = data.coder_workspace_owner.me.groups[0]
}
```

### Install a specific version of the Vault CLI

```tf
module "vault" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/coder/vault-jwt/coder"
  version           = "1.0.31"
  agent_id          = coder_agent.example.id
  vault_addr        = "https://vault.example.com"
  vault_jwt_role    = "coder" # The Vault role to use for authentication
  vault_cli_version = "1.17.5"
}
```

### Use a custom JWT token

```tf

terraform {
  required_providers {
    jwt = {
      source  = "geektheripper/jwt"
      version = "1.1.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.11.1"
    }
  }
}


resource "jwt_signed_token" "vault" {
  count     = data.coder_workspace.me.start_count
  algorithm = "RS256"
  # `openssl genrsa -out key.pem 4096` and `openssl rsa -in key.pem -pubout > pub.pem` to generate keys
  key = file("key.pem")
  claims_json = jsonencode({
    iss = "https://code.example.com"
    sub = "${data.coder_workspace.me.id}"
    aud = "https://vault.example.com"
    iat = provider::time::rfc3339_parse(plantimestamp()).unix
    # Uncomment to set an expiry on the JWT token(default 3600 seconds). 
    # workspace will need to be restarted to generate a new token if it expires
    #exp = provider::time::rfc3339_parse(timeadd(timestamp(), 3600)).unix    agent            = coder_agent.main.id
    provisioner      = data.coder_provisioner.main.id
    provisioner_arch = data.coder_provisioner.main.arch
    provisioner_os   = data.coder_provisioner.main.os

    workspace        = data.coder_workspace.me.id
    workspace_url    = data.coder_workspace.me.access_url
    workspace_port   = data.coder_workspace.me.access_port
    workspace_name   = data.coder_workspace.me.name
    template         = data.coder_workspace.me.template_id
    template_name    = data.coder_workspace.me.template_name
    template_version = data.coder_workspace.me.template_version
    owner            = data.coder_workspace_owner.me.id
    owner_name       = data.coder_workspace_owner.me.name
    owner_email      = data.coder_workspace_owner.me.email
    owner_login_type = data.coder_workspace_owner.me.login_type
    owner_groups     = data.coder_workspace_owner.me.groups
  })
}

module "vault" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/vault-jwt/coder"
  version         = "1.1.0"
  agent_id        = coder_agent.example.id
  vault_addr      = "https://vault.example.com"
  vault_jwt_role  = "coder" # The Vault role to use for authentication
  vault_jwt_token = jwt_signed_token.vault[0].token
}
```

#### Example Vault JWT role

```shell
vault write auth/JWT_MOUNT/role/workspace - << EOF
{
  "user_claim": "sub",
  "bound_audiences": "https://vault.example.com",
  "role_type": "jwt",
  "ttl": "1h",
  "claim_mappings": {
    "owner": "owner",
    "owner_email": "owner_email",
    "owner_login_type": "owner_login_type",
    "owner_name": "owner_name",
    "provisioner": "provisioner",
    "provisioner_arch": "provisioner_arch",
    "provisioner_os": "provisioner_os",
    "sub": "sub",
    "template": "template",
    "template_name": "template_name",
    "template_version": "template_version",
    "workspace": "workspace",
    "workspace_name": "workspace_name",
    "workspace_id": "workspace_id"
  }
}
EOF
```

#### Example workspace access Vault policy

```tf
path "kv/data/app/coder/{{identity.entity.aliases.<MOUNT_ACCESSOR>.metadata.owner_name}}/{{identity.entity.aliases.<MOUNT_ACCESSOR>.metadata.workspace_name}}" {
  capabilities          = ["create", "read", "update", "delete", "list", "subscribe"]
  subscribe_event_types = ["*"]
}
path "kv/metadata/app/coder/{{identity.entity.aliases.<MOUNT_ACCESSOR>.metadata.owner_name}}/{{identity.entity.aliases.<MOUNT_ACCESSOR>.metadata.workspace_name}}" {
  capabilities          = ["create", "read", "update", "delete", "list", "subscribe"]
  subscribe_event_types = ["*"]
}
```
