---
display_name: Parsec
description: Low-latency remote desktop streaming for gaming and creative work
icon: ../../../../.icons/desktop.svg
maintainer_github: glitchdoescode
verified: false
tags: [remote-desktop, streaming, gaming, creative, low-latency]
---

# Parsec

Automatically install and configure [Parsec](https://parsec.app/) for low-latency remote desktop access in your Coder workspace. Parsec provides near-zero latency streaming with up to 4K resolution at 60 FPS, making it ideal for gaming, video editing, and other graphics-intensive applications.

## Features

- **Ultra-low latency**: Near-zero latency for responsive remote desktop access
- **High performance**: Up to 4K resolution at 60 FPS with hardware acceleration
- **Cross-platform**: Connect from any device to your Linux workspace
- **Secure**: Peer-to-peer connections with enterprise-grade security
- **Optimized**: Built specifically for gaming and creative workflows

## Basic Usage

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/glitchdoescode/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Advanced Configuration

### Specify Installation Method

```tf
module "parsec" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/glitchdoescode/parsec/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.example.id
  installation_method = "deb"  # Options: "auto", "deb", "appimage"
}
```

### Disable Hardware Acceleration

```tf
module "parsec" {
  count                        = data.coder_workspace.me.start_count
  source                       = "registry.coder.com/glitchdoescode/parsec/coder"
  version                      = "1.0.0"
  agent_id                     = coder_agent.example.id
  enable_hardware_acceleration = false
}
```

### Complete Example with Grouping

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/glitchdoescode/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  # UI positioning
  order = 1
  group = "Remote Access"
  
  # Performance settings
  enable_hardware_acceleration = true
  installation_method         = "auto"
}
```

## Installation Methods

The module supports multiple installation methods:

- **`auto`** (default): Automatically detects your Linux distribution and chooses the best method
- **`deb`**: Uses the official DEB package for Ubuntu/Debian systems
- **`appimage`**: Uses the universal AppImage for maximum compatibility

## System Requirements

### Minimum Requirements

- Linux distribution (Ubuntu, Debian, Arch, Fedora, etc.)
- X11 or Wayland display server
- Audio system (PulseAudio or ALSA)
- Network connection

### Recommended for Best Performance

- Dedicated GPU (NVIDIA, AMD, or Intel)
- Hardware acceleration drivers installed
- Fast internet connection (minimum 5 Mbps)

## Supported Distributions

- ✅ Ubuntu 18.04+ (LTS recommended)
- ✅ Debian 10+
- ✅ Arch Linux
- ✅ Fedora 32+
- ✅ CentOS 8+
- ✅ Manjaro
- ✅ Pop!\_OS
- ✅ Most other Linux distributions via AppImage

## Getting Started

1. **Install the module** in your Coder template
2. **Start your workspace** - Parsec will install automatically
3. **Launch Parsec** from your applications menu or run `parsec` in terminal
4. **Create a Parsec account** at [parsec.app](https://parsec.app)
5. **Connect** from any device using the Parsec client

## Hardware Acceleration

When enabled (default), the module installs appropriate drivers for:

- **Intel**: VA-API drivers for Intel integrated graphics
- **NVIDIA**: VDPAU drivers for NVIDIA GPUs
- **AMD**: Mesa drivers for AMD GPUs

## Security

Parsec uses:

- **Peer-to-peer connections** - Traffic never goes through Parsec servers
- **AES-256 encryption** - All data is encrypted in transit
- **Host control** - You control exactly what guests can access

## Troubleshooting

### Audio Issues

If you don't hear audio, ensure your audio system is properly configured:

```bash
# Check audio system
pulseaudio --check -v

# Restart PulseAudio if needed
pulseaudio -k && pulseaudio --start
```

### Graphics Issues

For optimal performance, ensure graphics drivers are installed:

```bash
# Check for graphics acceleration
vainfo    # For VA-API
vdpauinfo # For VDPAU
```

### Connection Issues

- Ensure your firewall allows Parsec connections
- Check your network connection speed
- Verify Parsec service is running: `systemctl --user status parsec`

## Variables

| Variable                       | Type   | Default  | Description                                             |
| ------------------------------ | ------ | -------- | ------------------------------------------------------- |
| `agent_id`                     | string | -        | **Required.** The ID of a Coder agent                   |
| `installation_method`          | string | `"auto"` | Installation method: `"auto"`, `"deb"`, or `"appimage"` |
| `enable_hardware_acceleration` | bool   | `true`   | Enable hardware acceleration for optimal performance    |
| `order`                        | number | `null`   | Position in the Coder dashboard                         |
| `group`                        | string | `null`   | Group name for organization                             |
