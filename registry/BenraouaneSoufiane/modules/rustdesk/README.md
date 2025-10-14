---
display_name: RustDesk
description: Run RustDesk in your workspace with virtual display
icon: ../../../../.icons/rustdesk.svg
verified: false
tags: [rustdesk, rdp, vm]
---

# RustDesk

Launches RustDesk within your workspace with a virtual display to provide remote desktop access. The module outputs the RustDesk ID and password needed to connect from external RustDesk clients.

```tf
module "rustdesk" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/BenraouaneSoufiane/rustdesk/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- Automatically sets up virtual display (Xvfb)
- Downloads and configures RustDesk
- Outputs RustDesk ID and password for easy connection
- Provides external app link to RustDesk web client for browser-based access
- Starts virtual display (Xvfb) with customizable resolution
- Customizable screen resolution and RustDesk version

## Requirements

- Coder v2.5 or higher
- Linux workspace with `apt`, `dnf`, or `yum` package manager

## Examples

### Custom configuration with specific version

```tf
module "rustdesk" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/BenraouaneSoufiane/rustdesk/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  rustdesk_password = "mycustompass"
  xvfb_resolution   = "1920x1080x24"
  rustdesk_version  = "1.4.1"
}
```

### Docker container configuration

It requires coder' server to be run as root, when using with Docker, add the following to your `docker_container` resource:

```tf
resource "docker_container" "workspace" {

  # ... other configuration ...

  user         = "root"
  privileged   = true
  network_mode = "host"

  ports {
    internal = 21115
    external = 21115
  }
  ports {
    internal = 21116
    external = 21116
  }
  ports {
    internal = 21118
    external = 21118
  }
  ports {
    internal = 21119
    external = 21119
  }
}
```
