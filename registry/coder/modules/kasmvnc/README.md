---
display_name: KasmVNC
description: A modern open source VNC server
icon: ../../../../.icons/kasmvnc.svg
verified: true
tags: [vnc, desktop, kasmvnc]
---

# KasmVNC

Automatically install [KasmVNC](https://kasmweb.com/kasmvnc) in a workspace, and create an app to access it via the dashboard.

```tf
module "kasmvnc" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/kasmvnc/coder"
  version             = "1.2.1"
  agent_id            = coder_agent.example.id
  desktop_environment = "xfce"
  subdomain           = true
}
```

> **Note:** This module only works on workspaces with a pre-installed desktop environment. As an example base image you can use `codercom/enterprise-desktop` image.
