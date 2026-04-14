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
- Exports `AGENTAPI_BOUNDARY_PREFIX` as a workspace environment variable
- Provides the wrapper path via the `boundary_wrapper_path` output

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Usage

The `AGENTAPI_BOUNDARY_PREFIX` environment variable is automatically available to all
workspace processes. Start scripts should check for this variable and use it to prefix
commands that should run in network isolation:

```bash
if [ -n "${AGENTAPI_BOUNDARY_PREFIX:-}" ]; then
  # Run command with boundary wrapper
  "${AGENTAPI_BOUNDARY_PREFIX}" my-command --args
else
  # Run command normally
  my-command --args
fi
```

Alternatively, you can use the module output to access the wrapper path in Terraform:

```tf
module "boundary" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/boundary/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

resource "coder_script" "my_app" {
  agent_id = coder_agent.main.id
  script   = <<-EOT
    # Access the boundary wrapper path
    WRAPPER="${module.boundary[0].boundary_wrapper_path}"
    "$WRAPPER" my-command --args
  EOT
}
```

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
