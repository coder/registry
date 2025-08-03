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

- Windows or Linux-based workspace
- Parsec host key (obtain from [Parsec Settings](https://console.parsec.app/settings))
- For GPU acceleration:
  - Windows: NVIDIA or AMD GPU with latest drivers
  - Linux: NVIDIA GPU with appropriate drivers installed

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
   - Windows: Uses PowerShell to download and install Parsec
   - Linux: Uses shell script to install via package manager
2. **Configuration**: Sets up Parsec with the provided host key and settings
   - Creates platform-specific configuration files
   - Applies custom streaming settings
3. **GPU Support**: Automatically configures GPU acceleration if available
   - Windows: Supports both NVIDIA and AMD GPUs
   - Linux: Configures NVIDIA GPU drivers
4. **Autostart**: Optionally starts Parsec daemon on workspace startup
   - Windows: Configures Windows service
   - Linux: Sets up systemd service

## Client Setup

1. Download the [Parsec client](https://parsec.app/downloads) for your platform
2. Log in with your Parsec account
3. Your workspace will appear in the "Computers" list
4. Click to connect and start streaming

## Troubleshooting

### Stream Quality Issues
- If experiencing poor quality:
  - Reduce encoder_bitrate or encoder_fps
  - Check your network connection
  - Verify GPU acceleration is working
  
### Connection Problems
- If connection fails:
  - Verify your host key is correct
  - Check workspace firewall settings
  - Ensure Parsec daemon is running

### Platform-Specific Issues

#### Windows
- GPU not detected:
  - Update GPU drivers through Device Manager
  - For NVIDIA: Install latest Game Ready drivers
  - For AMD: Install latest Radeon Software
- Service not starting:
  - Check Windows Services app
  - Review Event Viewer for errors
  
#### Linux
- GPU acceleration not working:
  - Verify NVIDIA drivers are installed: `nvidia-smi`
  - Check X server configuration
- Display server issues:
  - Ensure X11 or Wayland is running
  - Check display server logs

## References

### Documentation
- [Parsec Documentation](https://parsec.app/docs)
- [Host Computer Requirements](https://parsec.app/docs/hosting-specifications)
- [Windows Setup Guide](https://parsec.app/docs/windows)
- [Linux Setup Guide](https://parsec.app/docs/linux)

### Support Resources
- [Parsec Support Center](https://support.parsec.app)
- [GPU Driver Downloads](https://parsec.app/docs/supported-graphics-cards)
- [Network Requirements](https://support.parsec.app/hc/en-us/articles/115002875791-Required-Network-Ports-And-Protocols)

### Community
- [Parsec Discord](https://discord.gg/parsec)
- [Coder Discussion Forum](https://github.com/coder/coder/discussions)
