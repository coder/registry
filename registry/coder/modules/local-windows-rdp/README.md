---
display_name: Windows RDP Desktop
description: Enable RDP on Windows and add a one-click Coder Desktop button for seamless access
icon: ../../../../.icons/desktop.svg
maintainer_github: coder
verified: false
tags: [rdp, windows, desktop, remote]
---

# Windows RDP Desktop

This module enables Remote Desktop Protocol (RDP) on Windows workspaces and adds a one-click button to launch RDP sessions directly through Coder Desktop. It provides a complete, standalone solution for RDP access without requiring manual configuration or port forwarding.

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Features

- ✅ **Standalone Solution**: Automatically configures RDP on Windows workspaces
- ✅ **One-click Access**: Launch RDP sessions directly through Coder Desktop
- ✅ **No Port Forwarding**: Uses Coder Desktop URI handling
- ✅ **Auto-configuration**: Sets up Windows firewall, services, and authentication
- ✅ **Secure**: Configurable credentials with sensitive variable handling
- ✅ **Customizable**: Display name, credentials, and UI ordering options

## What This Module Does

1. **Enables RDP** on the Windows workspace
2. **Sets the administrator password** for RDP authentication
3. **Configures Windows Firewall** to allow RDP connections
4. **Starts RDP services** automatically
5. **Creates a Coder Desktop button** for one-click access

## Requirements

- **Coder Desktop**: Must be installed on the client machine ([Download here](https://github.com/coder/coder/releases))
- **Windows Workspace**: The target workspace must be running Windows
- **Coder Agent**: Must be running on the Windows workspace

## Examples

### Basic Usage

Uses default credentials (Username: `Administrator`, Password: `coderRDP!`):

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### Custom Credentials

Set your own username and password:

```tf
module "rdp_desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/local-windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  username = "MyAdmin"
  password = "MySecurePassword123!"
}
```

### Custom Display and Agent

Configure display name and specify a different agent:

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
