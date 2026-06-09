---
display_name: Portable Desktop
description: Install the portabledesktop binary for lightweight Linux desktop sessions.
icon: ../../../../.icons/desktop.svg
verified: true
tags: [desktop, vnc, ai]
---

# Portable Desktop

Install [portabledesktop](https://github.com/coder/portabledesktop) for lightweight Linux desktop sessions over VNC. The binary is stored in the agent's script data directory and is automatically available on PATH via `CODER_SCRIPT_BIN_DIR`.

```tf
module "portabledesktop" {
  source   = "registry.coder.com/coder/portabledesktop/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Custom download URL with checksum verification

```tf
module "portabledesktop" {
  source   = "registry.coder.com/coder/portabledesktop/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  url      = "https://example.com/portabledesktop-linux-x64"
  sha256   = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

### Additionally copy to a system path

Use `install_dir` to copy the binary to a system-wide directory in addition to the default script data directory:

```tf
module "portabledesktop" {
  source      = "registry.coder.com/coder/portabledesktop/coder"
  version     = "0.1.0"
  agent_id    = coder_agent.example.id
  install_dir = "/usr/local/bin"
}
```
