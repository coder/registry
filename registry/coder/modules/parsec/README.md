---
display_name: Parsec
description: Enable low-latency remote desktop access using Parsec cloud gaming technology
icon: ../../../../.icons/parsec.svg
verified: true
tags: [remote-desktop, gaming, gpu, streaming]
---

# Parsec Module

This module integrates [Parsec](https://parsec.app/) into your workspace for low-latency remote desktop access. Parsec provides high-performance streaming optimized for gaming and real-time interaction.

## Features

- High-performance remote desktop streaming
- GPU acceleration support
- Configurable streaming quality
- Automatic startup options
- Cross-platform client support

## Prerequisites

- A Linux-based workspace
- Parsec host key (obtain from [Parsec Settings](https://console.parsec.app/settings))
- For GPU acceleration: NVIDIA GPU with appropriate drivers

## Usage

Basic usage:

```hcl
module "parsec" {
  source         = "registry.coder.com/coder/parsec/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  parsec_host_key = var.parsec_host_key
}
```

Advanced configuration:

```hcl
module "parsec" {
  source         = "registry.coder.com/coder/parsec/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  parsec_host_key = var.parsec_host_key
  
  enable_gpu_acceleration = true
  auto_start = true
  
  parsec_config = {
    encoder_bitrate = 50    # Mbps
    encoder_fps = 60
    bandwidth_limit = 100   # Mbps
    encoder_h265 = true
    client_keyboard_layout = "en-us"
  }
}
```

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| parsec_host_key | Parsec host key for authentication | string | required |
| parsec_version | Version of Parsec to install | string | "latest" |
| enable_gpu_acceleration | Enable GPU acceleration | bool | true |
| auto_start | Start Parsec daemon automatically | bool | true |
| parsec_config | Parsec configuration options | object | see below |

### parsec_config Options

```hcl
parsec_config = {
  encoder_bitrate = 50         # Streaming bitrate in Mbps (1-100)
  encoder_fps = 60             # Target framerate
  bandwidth_limit = 100        # Bandwidth limit in Mbps
  encoder_h265 = true         # Use H.265 encoding when available
  client_keyboard_layout = "en-us"  # Keyboard layout
}
```

## How it Works

1. **Installation**: The module installs Parsec and required dependencies
2. **Configuration**: Sets up Parsec with the provided host key and settings
3. **GPU Support**: Automatically configures GPU acceleration if available
4. **Autostart**: Optionally starts Parsec daemon on workspace startup

## Client Setup

1. Download the [Parsec client](https://parsec.app/downloads) for your platform
2. Log in with your Parsec account
3. Your workspace will appear in the "Computers" list
4. Click to connect and start streaming

## Troubleshooting

- If the stream quality is poor:
  - Reduce encoder_bitrate or encoder_fps
  - Check your network connection
  - Verify GPU acceleration is working
  
- If connection fails:
  - Verify your host key is correct
  - Check workspace firewall settings
  - Ensure Parsec daemon is running

## References

- [Parsec Documentation](https://parsec.app/docs)
- [Host Computer Requirements](https://parsec.app/docs/hosting-specifications)
- [Parsec Linux Setup Guide](https://parsec.app/docs/linux)
