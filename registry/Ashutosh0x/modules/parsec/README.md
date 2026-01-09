---
display_name: Parsec
description: Low-latency remote desktop access using Parsec for cloud gaming and remote work
icon: ../../../../.icons/desktop.svg
verified: false
tags: [remote-desktop, parsec, gaming, streaming, low-latency]
---

# Parsec

Enable low-latency remote desktop access to Coder workspaces using [Parsec](https://parsec.app/).

Parsec is a remote desktop solution optimized for low-latency streaming, making it ideal for:
- Cloud gaming
- Remote development with GPU-accelerated workloads
- Video editing and design work
- Any task requiring responsive remote access

```tf
module "parsec" {
  source   = "registry.coder.com/Ashutosh0x/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Prerequisites

- A Parsec account (free or paid)
- Linux workspace with desktop environment (for GUI access)
- GPU recommended for optimal performance

## Examples

### Basic Usage

```tf
module "parsec" {
  source   = "registry.coder.com/Ashutosh0x/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### With Custom Configuration

```tf
module "parsec" {
  source       = "registry.coder.com/Ashutosh0x/parsec/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  display_name = "Remote Desktop"
  headless     = true
}
```

## Features

- **Automatic Installation**: Parsec is installed automatically on workspace start
- **Headless Mode**: Run Parsec without a physical display attached
- **Auto-start**: Parsec service starts automatically with the workspace
- **Low Latency**: Optimized for responsive remote access

## Notes

- Users must authenticate with their Parsec account after first connection
- For best performance, use a workspace with a dedicated GPU
- Parsec supports both hardware and software encoding
