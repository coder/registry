---
display_name: Parsec
description: Install Parsec host on Windows workspaces
icon: ../../../../.icons/desktop.svg
verified: false
tags: [windows, remote-desktop, parsec]
---

# Parsec

Install Parsec on Windows workspaces and expose a dashboard link to launch the Parsec
client locally.

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

> [!IMPORTANT]
> Parsec hosting is supported on Windows (and macOS). This module targets Windows
> workspaces and expects a desktop environment plus a compatible GPU.

## Usage notes

1. The module installs Parsec silently on the workspace.
2. Sign in to Parsec on the workspace once (RDP or other remote access) to enable hosting.
3. Use the Parsec client locally to connect to the workspace.

## Configuration

```tf
module "parsec" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/parsec/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  display_name   = "Parsec"
  installer_url  = "https://builds.parsec.app/package/parsec-windows.exe"
  installer_args = "/S"
}
```
