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
- Writes a default boundary config to `~/.config/coder_boundary/config.yaml` (customizable)
- Exports `BOUNDARY_WRAPPER_PATH` and `BOUNDARY_CONFIG` as workspace environment variables
- Provides the wrapper path and config path via outputs

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}
```

## Configuration

The module ships with a comprehensive default config based on the
[Coder dogfood allowlist](./config.yaml). It covers Anthropic services,
version control, package managers, container registries, cloud platforms,
and common development tools.

By default the config is written to `~/.config/coder_boundary/config.yaml`
and the `BOUNDARY_CONFIG` env var points there. You can override it in two
ways:

### Inline config

Pass the full YAML content directly:

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  boundary_config = <<-YAML
    allowlist:
      - domain=your-deployment.coder.com
      - domain=api.anthropic.com
    log_dir: /tmp/boundary_logs
    proxy_port: 8087
    log_level: warn
  YAML
}
```

### External config file

Point to an existing config file in the workspace. The module will not
write any config and `BOUNDARY_CONFIG` will point to your path:

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  boundary_config_path = "/workspace/my-boundary-config.yaml"
}
```

> **Note:** `boundary_config` and `boundary_config_path` are mutually
> exclusive — setting both produces a validation error.

See the [Agent Firewall docs](https://coder.com/docs/ai-coder/agent-firewall)
for the full config reference.

## Usage

The `BOUNDARY_WRAPPER_PATH` environment variable is automatically available to all
workspace processes. Start scripts should check for this variable and use it to prefix
commands that should run in network isolation:

```bash
if [ -n "${BOUNDARY_WRAPPER_PATH:-}" ]; then
  # Run command with boundary wrapper
  "${BOUNDARY_WRAPPER_PATH}" -- my-command --args
fi
```

Alternatively, you can use the module output to access the wrapper path in Terraform:

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

resource "coder_script" "my_app" {
  agent_id = coder_agent.main.id
  script   = <<-EOT
    # Access the boundary wrapper path
    WRAPPER="${module.boundary[0].boundary_wrapper_path}"
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
network-isolated environment. The `coder_script` below waits for both
modules to finish installing before launching Claude behind the boundary
wrapper.

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

module "claude_code" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.3.0"
  agent_id = coder_agent.main.id
}

# Launch Claude behind the boundary wrapper after both modules
# have finished installing.
resource "coder_script" "claude_with_boundary" {
  agent_id     = coder_agent.main.id
  display_name = "Claude (Boundary)"
  run_on_start = true
  script       = <<-EOT
    # Wait for boundary and claude-code install scripts to complete.
    coder exp sync want claude-boundary \
      ${join(" ", module.boundary[0].scripts)} \
      ${join(" ", module.claude_code[0].scripts)}
    coder exp sync start claude-boundary

    # Run Claude inside the boundary wrapper.
    "$BOUNDARY_WRAPPER_PATH" -- claude
  EOT
}
```

### Compile from source

```tf
module "boundary" {
  count                        = data.coder_workspace.me.start_count
  source                       = "registry.coder.com/coder/boundary/coder"
  version                      = "0.0.1"
  agent_id                     = coder_agent.main.id
  compile_boundary_from_source = true
  boundary_version             = "main"
}
```

### Use release binary

```tf
module "boundary" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/coder/boundary/coder"
  version               = "0.0.1"
  agent_id              = coder_agent.main.id
  use_boundary_directly = true
  boundary_version      = "latest"
}
```
