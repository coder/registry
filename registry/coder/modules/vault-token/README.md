---
display_name: Hashicorp Vault Integration (Token)
description: Authenticates with Vault using Token
icon: ../../../../.icons/vault.svg
maintainer_github: coder
partner_github: hashicorp
verified: true
tags: [hashicorp, integration, vault, token]
---

# Hashicorp Vault Integration (Token)

This module lets you authenticate with [Hashicorp Vault](https://www.vaultproject.io/) in your Coder workspaces using a [Vault token](https://developer.hashicorp.com/vault/docs/auth/token).

```tf
variable "vault_token" {
  type        = string
  description = "The Vault token to use for authentication."
  sensitive   = true
}

module "vault" {
  source          = "registry.coder.com/coder/vault-token/coder"
  version         = "1.2.0"
  agent_id        = coder_agent.example.id
  vault_token     = var.token # optional
  vault_addr      = "https://vault.example.com"
  vault_namespace = "prod" # optional, vault enterprise only
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

## Configuration

To configure the Vault module, you must create a Vault token with the the required permissions and configure the module with the token and Vault address.

1. Create a vault policy with read access to the secret mount you need your developers to access.
   ```shell
   vault policy write read-coder-secrets - <<EOF
    path "coder/data/*" {
      capabilities = ["read"]
    }
    path "coder/metadata/*" {
      capabilities = ["read"]
    }
    EOF
   ```
2. Create a token using this policy.
   ```shell
   vault token create -policy="read-coder-secrets"
   ```
3. Copy the generated token and use in your template.

## Examples

### Configure Vault integration and install a specific version of the Vault CLI

```tf
variable "vault_token" {
  type        = string
  description = "The Vault token to use for authentication."
  sensitive   = true
}

module "vault" {
  source            = "registry.coder.com/coder/vault-token/coder"
  version           = "1.2.0"
  agent_id          = coder_agent.example.id
  vault_addr        = "https://vault.example.com"
  vault_token       = var.token
  vault_cli_version = "1.19.0"
}
```
