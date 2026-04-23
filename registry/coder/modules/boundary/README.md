---
display_name: Boundary
description: Configures boundary for network isolation in Coder workspaces
icon: ../../../../.icons/coder.svg
verified: true
tags: [boundary, coder, AI, agents]
---

# Boundary

Installs boundary for network isolation in Coder workspaces.

This module:

- Installs boundary (via coder subcommand, direct installation, or compilation from source)
- Creates a wrapper script at `$HOME/.coder-modules/coder/boundary/boundary-wrapper.sh`
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

## Usage

The `BOUNDARY_WRAPPER_PATH` environment variable is automatically available to all
workspace processes. Start scripts should check for this variable and use it to prefix
commands that should run in network isolation:

```bash
if [ -n "${BOUNDARY_WRAPPER_PATH:-}" ]; then
  # Run command with boundary wrapper
  "${BOUNDARY_WRAPPER_PATH}" --config=~/.config/coder_boundary/config.yaml --log-level=info -- my-command --args
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
    "$WRAPPER" ~/.config/coder_boundary/config.yaml -- my-command --args
  EOT
}
```

### Script Synchronization

The `sync_script_names` output provides a list of script names that can be used with `coder exp sync` to coordinate script execution. This is useful when your scripts need to wait for boundary installation to complete before running.

The list may contain the following script names:

- `coder_boundary-pre_install_script` - Pre-installation script (if configured)
- `coder_boundary-install_script` - Main boundary installation script
- `coder_boundary-post_install_script` - Post-installation script (if configured)

## Examples

### Compile from source

```tf
module "boundary" {
  count                        = data.coder_workspace.me.start_count
  source                       = "registry.coder.com/coder/boundary/coder"
  version                      = "1.0.0"
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
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  use_boundary_directly = true
  boundary_version      = "latest"
}
```
