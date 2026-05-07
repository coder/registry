---
display_name: Boundary
description: Configures boundary for network isolation in Coder workspaces
icon: ../../../../.icons/coder.svg
verified: true
tags: [boundary, ai, agents, firewall]
---

# Boundary

Installs [boundary](https://coder.com/docs/ai-coder/agent-firewall) for network isolation in Coder workspaces.

This module:

- Installs boundary (via coder subcommand, direct installation, or compilation from source)
- Creates a wrapper script at `$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh`
- Writes a default boundary config to `$HOME/.coder-modules/coder/boundary/config/config.yaml` (customizable)
- Provides the wrapper path, config path, and script names via outputs

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}
```

## Configuration

The module ships with a comprehensive default config based on the
[Coder dogfood allowlist](https://github.com/coder/coder/blob/main/dogfood/coder/boundary-config.yaml). It covers Anthropic services,
OpenAI services, version control, package managers, container registries,
cloud platforms, and common development tools.

The Coder deployment domain is automatically added to the allowlist using
`data.coder_workspace.me.access_url`.

By default the config is written to
`$HOME/.coder-modules/coder/boundary/config/config.yaml`. You can
access the resolved path via the `agent_firewall_config_path` output. Override
it in two ways:

### Inline config

Pass the full YAML content directly:

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  agent_firewall_config = <<-YAML
    allowlist:
      - domain=your-deployment.coder.com
      - domain=api.anthropic.com
      - domain=api.openai.com
    log_dir: /tmp/boundary_logs
    proxy_port: 8087
    log_level: warn
  YAML
}
```

### External config file

Point to an existing config file in the workspace. The module will not
write any config and the `agent_firewall_config_path` output will point to
your path:

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  agent_firewall_config_path = "/workspace/my-boundary-config.yaml"
}
```

> **Note:** `agent_firewall_config` and `agent_firewall_config_path` are mutually
> exclusive, setting both produces a validation error.

See the [Agent Firewall docs](https://coder.com/docs/ai-coder/agent-firewall)
for the full config reference.

## Usage

Use the `agent_firewall_wrapper_path` output to access the wrapper path in Terraform
and pass it to scripts that should run commands in network isolation:

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_script" "my_app" {
  agent_id = coder_agent.main.id
  script   = <<-EOT
    WRAPPER="${module.boundary.agent_firewall_wrapper_path}"
    "$WRAPPER" -- my-command --args
  EOT
}
```

### Script Synchronization

The `scripts` output provides a list of script names that can be used with `coder exp sync` to coordinate script execution. This is useful when your scripts need to wait for boundary installation to complete before running.

The list may contain the following script names:

- `coder-boundary-pre_install_script` - Pre-installation script (if configured)
- `coder-boundary-install_script` - Main boundary installation script
- `coder-boundary-post_install_script` - Post-installation script (if configured)

## Examples

### With Claude Code

Use boundary alongside the `claude-code` module to run Claude in a
network-isolated environment.

#### As an automated task

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_script" "claude_with_boundary" {
  agent_id     = coder_agent.main.id
  display_name = "Claude (Boundary)"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -e
    coder exp sync want claude-boundary \
      ${join(" ", module.boundary.scripts)} \
      ${join(" ", module.claude-code.scripts)}
    coder exp sync start claude-boundary
  "${module.boundary.agent_firewall_wrapper_path}" --config="${module.boundary.agent_firewall_config_path}" -- claude -p "Fix issue #840 from coder/coder"
  EOT
}
```

#### As a Coder app

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_app" "claude_with_boundary" {
  agent_id     = coder_agent.main.id
  display_name = "Claude Code"
  slug         = "claude-code"
  command      = <<-EOT
    #!/bin/bash
    set -e
    exec tmux new-session -A -s claude-code \
      '"${module.boundary.agent_firewall_wrapper_path}" --config="${module.boundary.agent_firewall_config_path}" -- claude'
  EOT
}
```
