---
display_name: Windows RDP Keep-Alive
description: Automatically extend workspace sessions during active RDP connections
icon: ../../../../.icons/rdp.svg
verified: false
tags: [windows, rdp, keep-alive, session]
---

# Windows RDP Keep-Alive

This module monitors active RDP (Remote Desktop Protocol) connections and keeps the Coder workspace alive while users are connected via RDP.

## Why Use This?

By default, Coder workspaces may time out after a period of inactivity. However, the standard activity detection doesn't include RDP connections. This module solves that by:

- Detecting active RDP sessions every 30 seconds (configurable)
- Bumping workspace activity when RDP connections are detected
- Preventing automatic workspace shutdown during active RDP sessions

## Usage

```tf
module "windows-rdp-keepalive" {
  source   = "registry.coder.com/coder/windows-rdp-keepalive/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### With Custom Check Interval

```tf
module "windows-rdp-keepalive" {
  source         = "registry.coder.com/coder/windows-rdp-keepalive/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  check_interval = 60  # Check every 60 seconds instead of default 30
}
```

### Combined with Windows RDP Module

```tf
module "windows-rdp" {
  source   = "registry.coder.com/coder/windows-rdp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

module "windows-rdp-keepalive" {
  source   = "registry.coder.com/coder/windows-rdp-keepalive/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## How It Works

1. The module starts a background PowerShell script on workspace startup
2. The script periodically checks for active RDP sessions using `qwinsta` and WMI
3. When an active RDP session is detected, it bumps the workspace activity
4. This prevents the workspace from being automatically stopped due to inactivity
5. When RDP sessions disconnect, normal timeout behavior resumes

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | string | required | The ID of a Coder agent |
| `check_interval` | number | 30 | Interval in seconds between RDP connection checks |
| `enabled` | bool | true | Whether to enable RDP keep-alive monitoring |

## Logs

The module logs activity to `%TEMP%\rdp-keepalive.log` for debugging purposes.

## Requirements

- Windows operating system
- Coder agent running on the workspace
- RDP enabled on the Windows machine
