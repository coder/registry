---
display_name: Moonlight/GameStream
description: GPU-accelerated remote desktop streaming with Moonlight and GameStream/Sunshine
icon: ../../../../.icons/moonlight.svg
verified: true
tags: [streaming, gpu, moonlight, gamestream, sunshine, remote-desktop]
---

# Moonlight/GameStream Remote Desktop

Automatically install and configure **Moonlight streaming** with either **NVIDIA GameStream** or **Sunshine server** for GPU-accelerated remote desktop access in your Coder workspace.

This module provides low-latency, high-quality streaming of your desktop and applications, making it ideal for:
- GPU-intensive workloads (machine learning, 3D rendering, gaming)
- High-performance remote desktop access
- Real-time application streaming
- Development environments requiring GPU acceleration

## Features

- **Dual Backend Support**: Choose between NVIDIA GameStream or Sunshine server
- **GPU Acceleration**: Leverages hardware encoding for optimal performance
- **Audio Streaming**: Full audio support with low latency
- **Gamepad Support**: Controller and gamepad input forwarding
- **Configurable Quality**: Customizable resolution, FPS, and bitrate
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **Web Interface**: Sunshine includes a web-based configuration UI

## Quick Start

### Basic Configuration (Sunshine - Recommended)

```tf
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
  streaming_server = "sunshine"
}
```

### NVIDIA GameStream Configuration

```tf
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
  streaming_server = "gamestream"
}
```

### Advanced Configuration

```tf
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
  
  # Server configuration
  streaming_server = "sunshine"
  port = 47990
  sunshine_version = "v0.22.2"
  
  # Quality settings
  resolution = "2560x1440"
  fps = 120
  bitrate = 50
  
  # Features
  enable_audio = true
  enable_gamepad = true
  
  # UI settings
  order = 1
  group = "Remote Desktop"
}
```

## Configuration Options

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | string | - | **Required.** The ID of a Coder agent |
| `streaming_server` | string | `"sunshine"` | Streaming backend: `"sunshine"` or `"gamestream"` |
| `port` | number | `47990` | Port for the streaming server web interface |
| `sunshine_version` | string | `"v0.22.2"` | Version of Sunshine to install |
| `enable_audio` | bool | `true` | Enable audio streaming support |
| `enable_gamepad` | bool | `true` | Enable gamepad/controller support |
| `resolution` | string | `"1920x1080"` | Default streaming resolution (WIDTHxHEIGHT) |
| `fps` | number | `60` | Default streaming frame rate (30-120) |
| `bitrate` | number | `20` | Default streaming bitrate in Mbps (5-150) |
| `subdomain` | bool | `true` | Enable subdomain sharing for web UI |
| `share` | string | `"owner"` | App sharing level: `"owner"`, `"authenticated"`, or `"public"` |
| `order` | number | `null` | UI presentation order |
| `group` | string | `null` | Group name for the app |

## Requirements

### System Requirements

**For Sunshine:**
- Linux, macOS, or Windows
- GPU with hardware encoding support (recommended)
- NVIDIA GPU with NVENC, AMD GPU with VCE, or Intel GPU with QuickSync

**For GameStream:**
- NVIDIA GPU (GTX 600 series or newer)
- NVIDIA GeForce Experience installed
- Windows 7/8/10/11 or Linux with NVIDIA drivers

### Network Requirements

- Open ports: Default 47990 (configurable)
- For remote streaming: Port forwarding or VPN setup
- Recommended: Gigabit network for 4K streaming

## Usage Guide

### 1. Initial Setup

After deployment, the module will:
- Install the selected streaming server (Sunshine/GameStream)
- Configure optimal streaming settings
- Set up required system dependencies
- Create helper scripts for connection info

### 2. Client Setup

Download and install the Moonlight client:
- **Windows/macOS/Linux**: https://moonlight-stream.org
- **Android**: Google Play Store
- **iOS**: App Store
- **NVIDIA Shield**: NVIDIA Games app

### 3. Connection Process

**For Sunshine:**
1. Access the Sunshine Web UI from your Coder dashboard
2. Set an admin password on first login
3. Add your client devices using the pairing PIN
4. Start streaming from your Moonlight client

**For GameStream:**
1. Ensure GeForce Experience is running
2. Enable GameStream in GeForce Experience settings
3. Add your client using the generated PIN
4. Connect using Moonlight client

### 4. Getting Connection Info

Run the generated helper script in your workspace terminal:
```bash
~/moonlight-info.sh
```

This displays:
- Server IP address
- Port configuration
- Quality settings
- Pairing information

## Streaming Quality Recommendations

| Use Case | Resolution | FPS | Bitrate | Notes |
|----------|------------|-----|---------|-------|
| **Office Work** | 1920x1080 | 30-60 | 10-15 Mbps | Balanced quality/bandwidth |
| **Development** | 2560x1440 | 60 | 25-35 Mbps | High resolution for coding |
| **Gaming** | 1920x1080 | 120 | 35-50 Mbps | High framerate priority |
| **4K Workstation** | 3840x2160 | 60 | 80-100 Mbps | Maximum quality |
| **Remote/Mobile** | 1280x720 | 30 | 5-10 Mbps | Bandwidth constrained |

## Troubleshooting

### Common Issues

**1. No GPU Detected**
- Install appropriate GPU drivers
- Verify GPU compatibility
- Consider software encoding as fallback

**2. Connection Refused**
- Check firewall settings
- Verify port configuration
- Ensure streaming service is running

**3. Poor Stream Quality**
- Adjust bitrate settings
- Check network bandwidth
- Verify GPU encoding capabilities

**4. Audio Issues**
- Ensure PulseAudio is running (Linux)
- Check audio device configuration
- Verify `enable_audio = true`

### Getting Help

1. Check service logs:
   ```bash
   # Sunshine logs
   tail -f /tmp/sunshine.log
   
   # System logs
   journalctl -u sunshine -f
   ```

2. Verify installation:
   ```bash
   ~/moonlight-info.sh
   ```

3. Test local connectivity:
   ```bash
   curl -k https://localhost:47990
   ```

## Security Considerations

- **Network Security**: Use VPN for external access
- **Authentication**: Set strong passwords for Sunshine web UI
- **Firewall**: Configure appropriate port restrictions
- **Updates**: Keep streaming software updated
- **Monitoring**: Monitor for unauthorized access attempts

## Performance Optimization

### GPU Settings
- Enable GPU scheduling (Windows)
- Set power mode to maximum performance
- Disable GPU power saving features

### Network Optimization
- Use wired connection when possible
- Enable QoS for streaming traffic
- Minimize network latency

### System Tuning
- Disable unnecessary background services
- Set high-performance power profile
- Ensure adequate cooling for sustained loads

## Comparison: Sunshine vs GameStream

| Feature | Sunshine | GameStream |
|---------|----------|------------|
| **GPU Support** | NVIDIA, AMD, Intel | NVIDIA only |
| **Platform Support** | Linux, Windows, macOS | Windows (Linux limited) |
| **Development Status** | Active | Deprecated |
| **Open Source** | Yes | No |
| **Web Interface** | Yes | No |
| **Future Support** | Long-term | End-of-life |

## Related Modules

- [`kasmvnc`](../kasmvnc/README.md) - VNC-based remote desktop
- [`windows-rdp`](../windows-rdp/README.md) - Windows RDP access
- [`vscode-desktop`](../vscode-desktop/README.md) - VS Code in browser

## Version History

- `1.0.0` - Initial release with Sunshine and GameStream support
