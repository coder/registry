---
display_name: Moonlight GameStream
description: Moonlight streaming support for GPU-accelerated remote desktop access in Coder workspaces (Windows & Linux)
icon: ../../../../.icons/moonlight.svg
verified: false
tags: [moonlight, gamestream, sunshine, remote-desktop, gpu, windows, linux]
---

# Moonlight GameStream

Enable [Moonlight](https://moonlight-stream.org/) for high-performance GPU-accelerated remote desktop streaming in your Coder workspace. Supports both Windows and Linux workspaces with automatic GPU detection and server configuration.

## Features

- **Automatic GPU Detection** - Identifies NVIDIA GPUs and compatible hardware
- **Smart Server Selection** - Automatically chooses GameStream or Sunshine based on hardware
- **Cross-Platform Support** - Windows and Linux compatibility
- **Quality Optimization** - Configurable streaming quality settings
- **Network Optimization** - Automatic port forwarding and firewall configuration

## Usage

```tf
module "moonlight" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/Majain004/moonlight/coder"
  version          = "1.0.0"
  agent_id         = resource.coder_agent.main.id
  os               = "windows" # or "linux"
  streaming_method = "auto"    # "auto", "gamestream", or "sunshine"
  port             = 47984
  quality          = "high"    # "low", "medium", "high", "ultra"
  subdomain        = true
}
```

## Requirements

- **Hardware**: NVIDIA GPU (for GameStream) or compatible GPU (for Sunshine)
- **Windows**: Windows 10+ with NVIDIA drivers (for GameStream)
- **Linux**: Desktop environment with GPU support
- **Network**: Outbound internet access for Moonlight client download
- **Moonlight Account**: Free account for authentication

## How it works

### Automatic Detection
1. **GPU Detection** - Identifies NVIDIA GPUs using system tools
2. **Method Selection** - Chooses GameStream (NVIDIA) or Sunshine (alternative)
3. **Server Setup** - Configures streaming server automatically
4. **Client Installation** - Installs Moonlight client for remote access

### Streaming Methods
- **GameStream**: Uses NVIDIA GameStream technology (requires NVIDIA GPU)
- **Sunshine**: Open-source GameStream server (works with any GPU)
- **Auto**: Automatically selects the best method based on hardware

### Quality Settings
- **Low**: 720p, 30fps - Good for basic remote access
- **Medium**: 1080p, 30fps - Balanced performance and quality
- **High**: 1080p, 60fps - Recommended for gaming
- **Ultra**: 4K, 60fps - Maximum quality (requires strong network)

## Configuration Options

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `streaming_method` | string | `"auto"` | Streaming method: "auto", "gamestream", "sunshine" |
| `port` | number | `47984` | Port for Moonlight streaming |
| `quality` | string | `"high"` | Streaming quality: "low", "medium", "high", "ultra" |
| `subdomain` | bool | `true` | Enable subdomain sharing |

## Notes

- **First Launch**: You may need to log in to Moonlight on first launch
- **Network**: Ensure proper network configuration for streaming
- **Performance**: GPU acceleration recommended for optimal performance
- **Compatibility**: Works best with NVIDIA GPUs for GameStream

## License

Moonlight is open source. See [Moonlight License](https://github.com/moonlight-stream/moonlight-qt/blob/master/LICENSE) for details. 