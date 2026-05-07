---
display_name: Agent Firewall
description: Configures agent-firewall for network isolation in Coder workspaces
icon: ../../../../.icons/coder.svg
verified: true
tags: [agent-firewall, ai, agents, firewall, boundary]
---

# Agent Firewall

Installs [agent-firewall](https://coder.com/docs/ai-coder/agent-firewall) for network isolation in Coder workspaces.

This module:

- Installs agent-firewall (via coder subcommand, direct installation, or compilation from source)
- Creates a wrapper script at `$HOME/.coder-modules/coder/agent-firewall/scripts/agent-firewall-wrapper.sh`
- Writes a [default agent-firewall config](./config.yaml.tftpl) to `$HOME/.coder-modules/coder/agent-firewall/config/config.yaml` (customizable)
- Provides the wrapper path, config path, and script names via outputs
- Uses coder-utils and output `scripts` for synchronization. https://registry.coder.com/modules/coder/coder-utils?tab=outputs

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}
```

## Examples

Use the `agent_firewall_wrapper_path` output to access the wrapper path and `agent_firewall_config_path` to access config path in Terraform and pass it to scripts that should run commands in network isolation.

### With Claude Code

Use agent-firewall alongside the `claude-code` module to run Claude in a
network-isolated environment.

#### As an automated task

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_script" "claude_with_agent_firewall" {
  agent_id     = coder_agent.main.id
  display_name = "Claude (Agent Firewall)"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -e
    coder exp sync want claude-agent-firewall \
      ${join(" ", module.agent-firewall.scripts)} \
      ${join(" ", module.claude-code.scripts)}
    coder exp sync start claude-agent-firewall
  "${module.agent-firewall.agent_firewall_wrapper_path}" --config="${module.agent-firewall.agent_firewall_config_path}" -- claude -p "Fix issue #840 from coder/coder"
  EOT
}
```

#### As a Coder app

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_app" "claude_with_agent_firewall" {
  agent_id     = coder_agent.main.id
  display_name = "Claude Code"
  slug         = "claude-code"
  command      = <<-EOT
    #!/bin/bash
    set -e
    exec tmux new-session -A -s claude-code \
      '"${module.agent-firewall.agent_firewall_wrapper_path}" --config="${module.agent-firewall.agent_firewall_config_path}" -- claude'
  EOT
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
`$HOME/.coder-modules/coder/agent-firewall/config/config.yaml`. You can
access the resolved path via the `agent_firewall_config_path` output. Override
it in two ways:

### Inline config

Pass the full YAML content directly:

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  agent_firewall_config = <<-YAML
    allowlist:
      - domain=your-deployment.coder.com
      - domain=api.anthropic.com
      - domain=api.openai.com
    log_dir: /tmp/agent_firewall_logs
    proxy_port: 8087
    log_level: warn
  YAML
}
```

### External config file

Point to an existing config file in the workspace. The module will not
write any config and the `agent_firewall_config_path` output will point to
your path. The file must exist on disk before agent-firewall starts.

```tf
module "agent-firewall" {
  source   = "registry.coder.com/coder/agent-firewall/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  agent_firewall_config_path = "/workspace/my-agent-firewall-config.yaml"
}
```

> **Note:** `agent_firewall_config` and `agent_firewall_config_path` are mutually
> exclusive, setting both produces a validation error.

See the [Agent Firewall docs](https://coder.com/docs/ai-coder/agent-firewall)
for the full config reference.

## References

- [Agent Firewall Documentation](https://coder.com/docs/ai-coder/agent-firewall)
