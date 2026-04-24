---
display_name: Coder Utils
description: Building block for modules that need orchestrated script execution
icon: ../../../../.icons/coder.svg
verified: false
tags: [internal, library]
---

# Coder Utils

> [!CAUTION]
> We do not recommend using this module directly. It is intended primarily for internal use by Coder to create modules with orchestrated script execution.

The Coder Utils module is a building block for modules that need to run multiple scripts in a specific order. It uses `coder exp sync` for dependency management and is designed for orchestrating pre-install, install, post-install, and start scripts.

```tf
module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "2.0.0"

  agent_id         = coder_agent.main.id
  module_directory = "$HOME/.coder-modules/coder/claude-code"

  pre_install_script = <<-EOT
    #!/bin/bash
    echo "Running pre-install tasks..."
    # Your pre-install logic here
  EOT

  install_script = <<-EOT
    #!/bin/bash
    echo "Installing dependencies..."
    # Your install logic here
  EOT

  post_install_script = <<-EOT
    #!/bin/bash
    echo "Running post-install configuration..."
    # Your post-install logic here
  EOT

  start_script = <<-EOT
    #!/bin/bash
    echo "Starting the application..."
    # Your start logic here
  EOT
}
```

## Execution Order

The module orchestrates scripts in the following order:

1. **Pre-Install Script** (optional) - Runs before installation
2. **Install Script** (required) - Main installation
3. **Post-Install Script** (optional) - Runs after installation
4. **Start Script** (optional) - Starts the application

Each script waits for its prerequisites to complete before running using `coder exp sync` dependency management.

## Customizing Script Display

By default each `coder_script` renders in the Coder UI as plain "Install Script", "Pre-Install Script", etc. Downstream modules can brand them:

```tf
module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "2.0.0"

  agent_id         = coder_agent.main.id
  module_directory = "$HOME/.coder-modules/coder/claude-code"
  install_script   = "echo installing"

  display_name_prefix = "Claude Code" # yields "Claude Code: Install Script", etc.
  icon                = "/icon/claude.svg"
}
```

Both variables are optional. `display_name_prefix` defaults to `""` (no prefix), and `icon` defaults to `null` (use the Coder provider's default).

## Log file locations

The module writes each script's stdout+stderr to `${module_directory}/logs/`:

- `pre_install.log`
- `install.log`
- `post_install.log`
- `start.log`

Each `coder_script` `mkdir -p`s this subdirectory before its `tee` runs, so the first script to execute creates it.

## Script file locations

The module materializes each script to `${module_directory}/scripts/` before running it:

- `pre_install.sh`
- `install.sh`
- `post_install.sh`
- `start.sh`

The pre-install and install `coder_script`s `mkdir -p` this subdirectory; post-install and start sync-depend on install, so the directory already exists by the time they run.
