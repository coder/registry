---
display_name: RDP Web
description: RDP Server and Web Client, powered by Devolutions Gateway
icon: ../../../../.icons/desktop.svg
verified: true
tags: [windows, rdp, web, desktop]
---

# Windows RDP

Enable Remote Desktop + a web based client on Windows workspaces, powered by [devolutions-gateway](https://github.com/Devolutions/devolutions-gateway).

The module adds an **RDP Desktop** app by default that opens the workspace in a
native RDP client through [Coder Desktop](https://coder.com/docs/user-guides/desktop).
Set `enable_native_rdp = false` for web-only access. The native app uses the same
administrator credentials as the web client and requires `agent_name`.

```tf
# AWS example. See below for examples of using this module with other providers
module "windows_rdp" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/windows-rdp/coder"
  version    = "1.4.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
}
```

## Video

[![Video](./video-thumbnails/video-thumbnail.png)](https://github.com/coder/modules/assets/28937484/fb5f4a55-7b69-4550-ab62-301e13a4be02)

## Examples

### With AWS

```tf
module "windows_rdp" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/windows-rdp/coder"
  version    = "1.4.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
}
```

### With Google Cloud

```tf
module "windows_rdp" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/windows-rdp/coder"
  version    = "1.4.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
}
```

### With Custom Devolutions Gateway Version

```tf
module "windows_rdp" {
  count                       = data.coder_workspace.me.start_count
  source                      = "registry.coder.com/coder/windows-rdp/coder"
  version                     = "1.4.0"
  agent_id                    = coder_agent.main.id
  agent_name                  = "main"
  devolutions_gateway_version = "2025.2.2" # Specify a specific version
}
```

### With Native RDP

Coder Desktop must be installed and connected on the local device. The agent
name must match the `coder_agent` resource passed through `agent_id`.

```tf
module "windows_rdp" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/windows-rdp/coder"
  version    = "1.4.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
}
```
