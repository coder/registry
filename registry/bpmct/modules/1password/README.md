---
display_name: "1Password"
description: "Install the 1Password CLI and VS Code extension in your Coder workspace"
icon: ../../../../.icons/1password.svg
verified: false
tags: [integration, 1password, secrets]
---

# 1Password

Install the [1Password CLI](https://developer.1password.com/docs/cli/)
(`op`) in your Coder workspace and optionally authenticate with a service
account token. Can also install the
[1Password VS Code extension](https://marketplace.visualstudio.com/items?itemName=1Password.op-vscode)
for code-server and VS Code.

```tf
module "onepassword" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/bpmct/1password/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  service_account_token = var.op_service_account_token
}
```

## Authentication

### Service Account (recommended)

Create a [1Password service account](https://developer.1password.com/docs/service-accounts/get-started/)
and pass the token as a Terraform variable. The module sets
`OP_SERVICE_ACCOUNT_TOKEN` in the workspace so `op` commands work
immediately.

```tf
variable "op_service_account_token" {
  type      = string
  sensitive = true
}

module "onepassword" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/bpmct/1password/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  service_account_token = var.op_service_account_token
}
```

### Personal Account

Pass your account details and the module will pre-register the account.
You'll be prompted for your password when you run `op signin` in the
terminal.

```tf
module "onepassword" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/bpmct/1password/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.main.id
  account_address    = "myteam.1password.com"
  account_email      = "you@example.com"
  account_secret_key = var.op_secret_key
}
```

## VS Code Extension

Set `install_vscode_extension = true` to install the 1Password extension
for code-server and VS Code.

```tf
module "onepassword" {
  count                    = data.coder_workspace.me.start_count
  source                   = "registry.coder.com/bpmct/1password/coder"
  version                  = "1.0.0"
  agent_id                 = coder_agent.main.id
  service_account_token    = var.op_service_account_token
  install_vscode_extension = true
}
```
