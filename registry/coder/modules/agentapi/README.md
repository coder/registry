---
display_name: AgentAPI
description: Building block for modules that need to run an AgentAPI server
icon: ../../../../.icons/coder.svg
verified: true
tags: [internal, library]
---

# AgentAPI

> [!CAUTION]
> We do not recommend using this module directly. Instead, please consider using one of our [Tasks-compatible AI agent modules](https://registry.coder.com/modules?search=tag%3Atasks).

The AgentAPI module is a building block for modules that need to run an AgentAPI server. It is intended primarily for internal use by Coder to create modules compatible with Tasks.

```tf
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "2.2.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Goose"
  cli_app_slug         = "goose-cli"
  cli_app_display_name = "Goose CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_PROVIDER='${var.goose_provider}' \
    ARG_MODEL='${var.goose_model}' \
    ARG_GOOSE_CONFIG="$(echo -n '${base64encode(local.combined_extensions)}' | base64 -d)" \
    ARG_INSTALL='${var.install_goose}' \
    ARG_GOOSE_VERSION='${var.goose_version}' \
    /tmp/install.sh
  EOT
}
```

## Task log snapshot

Captures the last 10 messages from AgentAPI when a task workspace stops. This allows viewing conversation history while the task is paused.

To enable for task workspaces:

```tf
module "agentapi" {
  # ... other config
  task_log_snapshot = true # default: true
}
```

## State Persistence

AgentAPI can save and restore conversation state across workspace restarts.
This is disabled by default and requires agentapi binary >= v0.12.0.

State and PID files are stored in `$HOME/<module_dir_name>/` alongside other
module files (e.g. `$HOME/.claude-module/agentapi-state.json`).

To enable:

```tf
module "agentapi" {
  # ... other config
  enable_state_persistence = true
}
```

To override file paths:

```tf
module "agentapi" {
  # ... other config
  state_file_path = "/custom/path/state.json"
  pid_file_path   = "/custom/path/agentapi.pid"
}
```

## Boundary (Network Filtering)

The agentapi module supports optional [Agent Boundaries](https://coder.com/docs/ai-coder/agent-boundaries)
for network filtering. When enabled, the module sets up a `AGENTAPI_BOUNDARY_PREFIX` environment
variable that points to a wrapper script. Agent modules should use this prefix in their
start scripts to run the agent process through boundary.

Boundary requires a `config.yaml` file with your allowlist, jail type, proxy port, and log
level. See the [Agent Boundaries documentation](https://coder.com/docs/ai-coder/agent-boundaries)
for configuration details.
To enable:

```tf
module "agentapi" {
  # ... other config
  enable_boundary      = true
  boundary_config_path = "/home/coder/.config/coder_boundary/config.yaml"

  # Optional: install boundary binary instead of using coder subcommand
  # use_boundary_directly        = true
  # boundary_version              = "0.6.0"
  # compile_boundary_from_source  = false
}
```

### Contract for agent modules

When `enable_boundary = true`, the agentapi module exports `AGENTAPI_BOUNDARY_PREFIX`
as an environment variable pointing to a wrapper script. Agent module start scripts
should check for this variable and use it to prefix the agent command:

```bash
if [ -n "${AGENTAPI_BOUNDARY_PREFIX:-}" ]; then
  agentapi server -- "${AGENTAPI_BOUNDARY_PREFIX}" my-agent "${ARGS[@]}" &
else
  agentapi server -- my-agent "${ARGS[@]}" &
fi
```

This ensures only the agent process is sandboxed while agentapi itself runs unrestricted.

## For module developers

For a complete example of how to use this module, see the [Goose module](https://github.com/coder/registry/blob/main/registry/coder/modules/goose/main.tf).
