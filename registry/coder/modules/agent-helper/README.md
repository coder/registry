---
display_name: Agent Helper
description: Building block for modules that need orchestrated script execution
icon: ../../../../.icons/coder.svg
verified: false
tags: [internal, library]
---

# Agent Helper

> [!CAUTION]
> We do not recommend using this module directly. It is intended primarily for internal use by Coder to create modules with orchestrated script execution.

The Agent Helper module is a building block for modules that need to run multiple scripts in a specific order. It uses `coder exp sync` for dependency management and is designed for orchestrating pre-install, install, post-install, and start scripts.

> [!NOTE]
>
> - The `agent_name` should be the same as that of the agentapi module's `agent_name` if used together.

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

The module orchestrates scripts in the following order:

1. **Log File Creation** - Creates module directory and log files
2. **Pre-Install Script** (optional) - Runs before installation
3. **Install Script** - Main installation
4. **Post-Install Script** (optional) - Runs after installation
5. **Start Script** - Starts the application

Each script waits for its prerequisites to complete before running using `coder exp sync` dependency management.
