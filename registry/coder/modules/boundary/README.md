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
- Automatically adds your Coder deployment domain to the config allowlist
- Exports `BOUNDARY_CONFIG` as a workspace environment variable
- Provides the wrapper path, config path, and script names via outputs

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
OpenAI services, version control, package managers, container registries,
cloud platforms, and common development tools.

The Coder deployment domain is automatically added to the allowlist using
`data.coder_workspace.me.access_url`.

By default the config is written to
`$HOME/.coder-modules/coder/boundary/config/config.yaml` and the
`BOUNDARY_CONFIG` env var points there. You can override it in two ways:

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
      - domain=api.openai.com
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

Use the `boundary_wrapper_path` output to access the wrapper path in Terraform
and pass it to scripts that should run commands in network isolation:

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
network-isolated environment. The `coder_app` below waits for both
modules to finish installing before launching Claude behind the boundary
wrapper.

```tf
module "boundary" {
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}

module "claude_code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.3.0"
  agent_id = coder_agent.main.id
}

resource "coder_app" "claude_with_boundary" {
  agent_id     = coder_agent.main.id
  slug         = "claude-cli"
  display_name = "Claude (Boundary)"
  command      = <<-EOT
    # Wait for boundary and claude-code install scripts to complete.
    coder exp sync want claude-boundary \
      ${join(" ", module.boundary.scripts)} \
      ${join(" ", module.claude_code.scripts)} > /dev/null 2>&1
    coder exp sync start claude-boundary > /dev/null 2>&1

    # Run Claude inside the boundary wrapper.
    "${module.boundary.boundary_wrapper_path}" \
      --config="${module.boundary.boundary_config_path}" -- claude
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
