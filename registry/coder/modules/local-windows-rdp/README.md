---
display_name: RDP Desktop
description: Enable RDP on Windows and add a one-click Coder Desktop button for seamless access
icon: ../../../../.icons/rdp.svg
maintainer_github: coder
verified: true
supported_os: [windows]
tags: [rdp, windows, desktop, local]
---

# Windows RDP Desktop

This module enables Remote Desktop Protocol (RDP) on Windows workspaces and adds a one-click button to launch RDP sessions directly through [Coder Desktop](https://coder.com/docs/user-guides/desktop). It provides a complete, standalone solution for RDP access, eliminating the need for manual configuration or port forwarding through the Coder CLI.

<!--
  2025-07-07 - Prettier isn't formatting GFM comments properly if they don't
  start with a letter.
  See https://github.com/prettier/prettier/issues/15479
-->
<!-- prettier-ignore -->
> [!NOTE]
> [Coder Desktop](https://coder.com/docs/user-guides/desktop) is required on client devices to use the Local Windows RDP access feature.

```tf
module "rdp_desktop" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/local-windows-rdp/coder"
  version    = "1.0.1"
  agent_id   = coder_agent.main.id
  agent_name = coder_agent.main.name
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

## Examples

### Basic Usage

Uses default credentials (Username: `Administrator`, Password: `coderRDP!`):

```tf
module "rdp_desktop" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/local-windows-rdp/coder"
  version    = "1.0.1"
  agent_id   = coder_agent.main.id
  agent_name = coder_agent.main.name
}
```

### Custom display name

Specify a custom display name for the `coder_app` button:

```tf
module "rdp_desktop" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/local-windows-rdp/coder"
  version      = "1.0.1"
  agent_id     = coder_agent.windows.id
  agent_name   = "windows"
  display_name = "Windows Desktop"
  order        = 1
}
```
