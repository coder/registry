---
display_name: Parsec
description: Low-latency remote desktop access using Parsec for cloud gaming and remote work
icon: https://upload.wikimedia.org/wikipedia/commons/8/87/Parsec_icon.png
verified: false
tags: [remote-desktop, parsec, gaming, streaming, low-latency, windows, linux]
---

# Parsec

Enable low-latency remote desktop access to Coder workspaces using [Parsec](https://parsec.app/).

Parsec is a remote desktop solution optimized for low-latency streaming, making it ideal for:
- Cloud gaming
- Remote development with GPU-accelerated workloads
- Video editing and design work
- Any task requiring responsive remote access

## Platform Support

- **Windows**: Fully supported (Hosting + Client). Ideal for remote desktop access to the workspace.
- **Linux**: Client support only. Hosting on Linux is not officially supported by Parsec at this time. Use this module on Linux if you need the Parsec **client** installed in your workspace (e.g., to connect *from* the workspace to another machine).

## Prerequisites

- A Parsec account (free or paid)
- **Windows Workspace** (for Hosting/Remote Desktop access)
- GPU recommended for optimal performance

## Examples

### Windows Workspace (Recommended)

```tf
module "parsec" {
  source   = "registry.coder.com/Ashutosh0x/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  os       = "windows"
}
```

### Linux Workspace (Client Only)

```tf
module "parsec" {
  source   = "registry.coder.com/Ashutosh0x/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  os       = "linux"
}
```

## Features

- **Automatic Installation**: Parsec is installed automatically on workspace start
- **Windows Support**: Silent installation for Windows workspaces (Service Mode)
- **Headless Mode**: Configures virtual display for headless operation (where supported)
- **Low Latency**: Optimized for responsive remote access

## Notes

- Users need to log in to their Parsec account.
- On **Windows**, Parsec installs in Shared mode, allowing access even at the login screen.
- On **Linux**, Parsec is installed as a client application.
