---
display_name: Agent Helper
description: Helper module for orchestrating script execution with proper dependencies
icon: ../../../../.icons/coder.svg
verified: false
tags: [internal, library, helper]
---

# Agent Helper

> [!CAUTION]
> This is an internal helper module intended for use by other Coder modules. Direct use is not recommended.

The Agent Helper module orchestrates the execution of multiple scripts in a specific order using `coder exp sync` for dependency management. It's designed as a building block for modules that need to run pre-install, install, post-install, and start scripts with proper synchronization.

## Features

- **Ordered execution**: Ensures scripts run in the correct sequence using `coder exp sync`
- **Optional scripts**: Pre-install and post-install scripts are optional
- **Log management**: Automatically creates and manages log files for each script
- **Dependency handling**: Properly chains script dependencies for reliable execution

## Usage

```tf
module "agent_helper" {
  source  = "registry.coder.com/coder/agent-helper/coder"
  version = "1.0.0"

  agent_id        = coder_agent.main.id
  agent_name      = "myagent"
  module_dir_name = ".my-module"

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

1. **Log File Creation**: Creates the module directory and log files
2. **Pre-Install Script** (if provided): Runs before installation
3. **Install Script**: Runs the main installation
4. **Post-Install Script** (if provided): Runs after installation
5. **Start Script**: Starts the application

The dependency chain ensures each script waits for its prerequisites to complete before running.

## Log Files

All script output is logged to separate files in the module directory:

- `$HOME/{module_dir_name}/pre_install.log` (if pre_install_script is provided)
- `$HOME/{module_dir_name}/install.log`
- `$HOME/{module_dir_name}/post_install.log` (if post_install_script is provided)
- `$HOME/{module_dir_name}/start.log`
