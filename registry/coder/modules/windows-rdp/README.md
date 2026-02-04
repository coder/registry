---
display_name: RDP Web
description: RDP Server and Web Client, powered by Devolutions Gateway
icon: ../../../../.icons/desktop.svg
verified: true
tags: [windows, rdp, web, desktop]
---

# Windows RDP

Enable Remote Desktop + a web based client on Windows workspaces, powered by [devolutions-gateway](https://github.com/Devolutions/devolutions-gateway).

```tf
# AWS example. See below for examples of using this module with other providers
module "windows_rdp" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windows-rdp/coder"
  version  = "1.4.0"
  agent_id = coder_agent.main.id
}
```

## Video

[![Video](./video-thumbnails/video-thumbnail.png)](https://github.com/coder/modules/assets/28937484/fb5f4a55-7b69-4550-ab62-301e13a4be02)

## Examples

### With AWS

```tf
module "windows_rdp" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windows-rdp/coder"
  version  = "1.4.0"
  agent_id = coder_agent.main.id
}
```

### With Google Cloud

```tf
module "windows_rdp" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/windows-rdp/coder"
  version  = "1.4.0"
  agent_id = coder_agent.main.id
}
```

### With Custom Devolutions Gateway Version

```tf
module "windows_rdp" {
  count                       = data.coder_workspace.me.start_count
  source                      = "registry.coder.com/coder/windows-rdp/coder"
  version                     = "1.4.0"
  agent_id                    = coder_agent.main.id
  devolutions_gateway_version = "2025.2.2" # Specify a specific version
}
```

### With Keep-Alive for Active RDP Sessions

Enable automatic workspace session extension while RDP connections are active. This prevents workspace shutdown during remote desktop use:

```tf
module "windows_rdp" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/windows-rdp/coder"
  version            = "1.4.0"
  agent_id           = coder_agent.main.id
  keepalive          = true # Enable RDP connection monitoring
  keepalive_interval = 300  # Check every 5 minutes (default)
}
```

The keep-alive feature monitors active RDP connections (port 3389) and reports workspace activity to Coder. When enabled:

- Workspace remains active while RDP sessions are connected
- Activity checks occur at the specified interval (default: 5 minutes)
- Session timeout resumes normal countdown after RDP disconnection
- No manual intervention required from users
