---
display_name: Parsec Cloud Gaming
description: Parsec remote desktop and cloud gaming integration for Coder workspaces (Windows & Linux)
icon: ../../../../.icons/parsec.svg
verified: false
tags: [parsec, cloud-gaming, remote-desktop, windows, linux]
---

# Parsec Cloud Gaming

Enable [Parsec](https://parsec.app/) for high-performance remote desktop and cloud gaming in your Coder workspace. Supports both Windows and Linux workspaces.

## Usage

```tf
module "parsec" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/parsec/coder"
  version    = "1.0.0"
  agent_id   = resource.coder_agent.main.id
  os         = "windows" # or "linux"
  port       = 8000
  subdomain  = true
}
```

## Requirements

- **Windows:** Windows 10+ with GPU support
- **Linux:** Desktop environment and GPU support recommended
- Outbound internet access to download Parsec
- Parsec account for login

## How it works

- Installs Parsec on the workspace (Windows: via PowerShell, Linux: via Bash)
- Exposes a Coder app to launch/connect to Parsec
- For Linux, ensure a desktop environment and X server are available

## Notes

- You may need to log in to Parsec on first launch
- For best performance, use a workspace with a GPU
- This module does not configure GPU passthrough or drivers

## License

Parsec is free for personal use. See [Parsec Terms](https://parsec.app/legal/terms) for details.