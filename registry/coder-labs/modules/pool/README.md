---
display_name: Pool CLI
icon: ../../../../.icons/poolside.svg
description: Install and configure Poolside's Pool coding agent in your workspace.
verified: false
tags: [agent, poolside, pool, ai, ai-gateway]
---

# Pool CLI

Install and configure [Pool](https://docs.poolside.ai/cli/pool), Poolside's coding agent, in your workspace.

```tf
module "pool" {
  source   = "registry.coder.com/coder-labs/pool/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id

  poolside_api_key = var.poolside_api_key
}
```

The module accepts Pool's EULA noninteractively during installation, installs the CLI in `~/.local/bin` by default, and makes `pool` available to Coder scripts and interactive shells.

## AI Gateway

[AI Gateway](https://coder.com/docs/ai-coder/ai-gateway) is a Premium Coder feature that provides centralized LLM proxy management. Requires Coder >= 2.30.0.

Pool supports OpenAI-compatible endpoints through `POOLSIDE_STANDALONE_BASE_URL`. Set `enable_ai_gateway = true` to configure the Coder AI Gateway endpoint and authenticate Pool with the workspace owner's Coder session token.

```tf
module "pool" {
  source   = "registry.coder.com/coder-labs/pool/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id

  enable_ai_gateway = true
  model             = "gpt-5"
}
```

> [!CAUTION]
> `enable_ai_gateway = true` is mutually exclusive with `poolside_api_key` and `standalone_base_url`. AI Gateway supplies both the endpoint and authentication.

## OpenAI-compatible endpoints

Use `standalone_base_url` to configure another OpenAI-compatible proxy or local inference server. Provide `poolside_api_key` when that endpoint requires authentication; `model` selects the model if the endpoint does not provide a default.

```tf
module "pool" {
  source   = "registry.coder.com/coder-labs/pool/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id

  poolside_api_key   = var.gateway_api_key
  standalone_base_url = "https://gateway.example.com/v1"
  model              = "my-coding-model"
}
```

For a Poolside deployment, use `poolside_api_url` to set `POOLSIDE_API_URL` instead.

## Existing installations

Set `install_pool = false` when Pool CLI is already present in your workspace image. Configure `pool_binary_path` if the binary is in a directory other than `~/.local/bin`.

## Serialize a downstream `coder_script` after installation

The `scripts` output is an ordered list of `coder exp sync` names created by the module.

```tf
resource "coder_script" "verify_pool" {
  agent_id     = coder_agent.main.id
  display_name = "Verify Pool CLI"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    trap 'coder exp sync complete verify-pool' EXIT
    coder exp sync want verify-pool ${join(" ", module.pool.scripts)}
    coder exp sync start verify-pool

    pool --version
  EOT
}
```

## Troubleshooting

The module's script logs are under `~/.coder-modules/coder-labs/pool/logs/`.

```bash
cat ~/.coder-modules/coder-labs/pool/logs/install.log
cat ~/.coder-modules/coder-labs/pool/logs/pre_install.log
cat ~/.coder-modules/coder-labs/pool/logs/post_install.log
```

## References

- [Pool CLI documentation](https://docs.poolside.ai/cli/pool)
- [Pool CLI installation](https://docs.poolside.ai/cli/install)
- [AI Gateway](https://coder.com/docs/ai-coder/ai-gateway)
