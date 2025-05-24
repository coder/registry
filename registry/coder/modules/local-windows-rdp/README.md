---
display_name: Windows RDP Desktop
description: Add a one-click RDP Desktop button using Coder Desktop URI functionality
icon: ../../../../.icons/desktop.svg
maintainer_github: coder
verified: true
tags: [rdp, windows, desktop]
---

# Windows RDP Desktop

This module adds a one-click button to launch Remote Desktop Protocol (RDP) sessions directly through Coder Desktop using URI handling. This provides seamless RDP access without requiring manual port forwarding.

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Requirements

- **Coder Desktop**: This module requires [Coder Desktop](https://github.com/coder/coder/releases) to be installed on the client machine
- **Windows Workspace**: The target workspace must be running Windows with RDP enabled
- **Agent**: A Coder agent must be running on the Windows workspace

## Features

- ✅ One-click RDP access through Coder Desktop
- ✅ No manual port forwarding required
- ✅ Configurable authentication credentials
- ✅ Customizable display name and ordering
- ✅ Secure credential handling

## Examples

### Basic Usage

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### Custom Credentials

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  username = "MyUser"
  password = "MySecurePassword123!"
}
```

### Custom Display and Agent

```tf
module "rdp_desktop" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/local-windows-rdp/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.windows.id
  agent_name   = "windows"
  display_name = "Windows Desktop"
  order        = 1
}
```
