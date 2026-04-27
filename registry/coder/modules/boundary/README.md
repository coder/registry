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
- Exports `BOUNDARY_WRAPPER_PATH` as a workspace environment variable
- Provides the wrapper path via the `boundary_wrapper_path` output

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}
```

## Configuration

Boundary reads its policy from a `config.yaml` file. A sample is included in
this module at [`config.yaml`](./config.yaml). Copy it into your template
directory and customize the `allowlist` for the domains your agent needs.

See the [Agent Firewall docs](https://coder.com/docs/ai-coder/agent-firewall)
for the full config reference.

To write the config into the workspace at startup, use a `coder_script`:

```tf
resource "coder_script" "boundary_config" {
  agent_id     = coder_agent.main.id
  display_name = "Boundary Config"
  run_on_start = true
  script       = <<-EOT
    mkdir -p ~/.config/coder_boundary
    cp ${path.module}/config.yaml ~/.config/coder_boundary/config.yaml
  EOT
}
```

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

# Write boundary config into the workspace.
resource "coder_script" "boundary_config" {
  agent_id     = coder_agent.main.id
  display_name = "Boundary Config"
  run_on_start = true
  script       = <<-EOT
    mkdir -p ~/.config/coder_boundary
    cp ${path.module}/config.yaml ~/.config/coder_boundary/config.yaml
  EOT
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
