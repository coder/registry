---
display_name: Vault CLI
description: Installs the Hashicorp Vault CLI and optionally configures token authentication
icon: ../../../../.icons/vault.svg
verified: true
tags: [helper, integration, vault, cli]
---

# Vault CLI

Installs the [Vault](https://www.vaultproject.io/) CLI and optionally configures token authentication. This module focuses on CLI installation and can be used standalone or as a base for other authentication methods.

## Prerequisites

The following tools are required in the workspace image:

- **HTTP client**: `curl`, `wget`, or `busybox` (at least one)
- **Archive utility**: `unzip` or `busybox` (at least one)

**Recommended:**

- **jq**: For reliable JSON parsing of the HashiCorp releases API (falls back to sed if not available)

```tf
module "vault_cli" {
  source     = "registry.coder.com/coder/vault-cli/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  vault_addr = "https://vault.example.com"
}
```

## With Token Authentication

If you have a Vault token, you can provide it to automatically configure authentication:

```tf
module "vault_cli" {
  source      = "registry.coder.com/coder/vault-cli/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  vault_addr  = "https://vault.example.com"
  vault_token = var.vault_token # Optional
}
```

## Examples

### Basic Installation (CLI Only)

Install the Vault CLI without any authentication:

```tf
module "vault_cli" {
  source     = "registry.coder.com/coder/vault-cli/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  vault_addr = "https://vault.example.com"
}
```

### With Specific Version

```tf
module "vault_cli" {
  source            = "registry.coder.com/coder/vault-cli/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  vault_addr        = "https://vault.example.com"
  vault_cli_version = "1.15.0"
}
```

### Custom Installation Directory

```tf
module "vault_cli" {
  source      = "registry.coder.com/coder/vault-cli/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  vault_addr  = "https://vault.example.com"
  install_dir = "/home/coder/bin"
}
```

### With Vault Enterprise Namespace

For Vault Enterprise users who need to specify a namespace:

```tf
module "vault_cli" {
  source          = "registry.coder.com/coder/vault-cli/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.example.id
  vault_addr      = "https://vault.example.com"
  vault_token     = var.vault_token
  vault_namespace = "admin/my-namespace"
}
```

## Related Modules

For more advanced authentication methods, see:

- [vault-github](https://registry.coder.com/modules/coder/vault-github) - Authenticate with Vault using GitHub tokens
- [vault-jwt](https://registry.coder.com/modules/coder/vault-jwt) - Authenticate with Vault using OIDC/JWT

For simple token-based authentication, see:

- [vault-token](https://registry.coder.com/modules/coder/vault-token) - Authenticate with Vault using a token
