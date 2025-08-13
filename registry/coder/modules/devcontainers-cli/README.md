---
display_name: devcontainers-cli
description: devcontainers-cli module provides an easy way to install @devcontainers/cli into a workspace
icon: ../../../../.icons/devcontainers.svg
verified: true
tags: [devcontainers]
---

# devcontainers-cli

The devcontainers-cli module provides an easy way to install [`@devcontainers/cli`](https://github.com/devcontainers/cli) into a workspace. It can be used within any workspace as it runs only if
@devcontainers/cli is not installed yet.
`npm` is required and should be pre-installed in order for the module to work.

```tf
module "devcontainers-cli" {
  source   = "registry.coder.com/coder/devcontainers-cli/coder"
  version  = "1.0.32"
  agent_id = coder_agent.example.id
}
```
