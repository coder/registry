Closes #206

## Description

This PR adds **Moonlight/GameStream remote desktop integration** to the Coder registry, enabling GPU-accelerated remote desktop streaming for high-performance workspaces. The implementation provides comprehensive support for both NVIDIA GameStream and Sunshine server, making it ideal for GPU-intensive workloads, machine learning, 3D rendering, and development environments requiring hardware acceleration.

### Key Features Added:
- **Dual Backend Support**: Choose between NVIDIA GameStream or Sunshine server
- **GPU Acceleration**: Leverages hardware encoding (NVENC, VCE, QuickSync) for optimal performance
- **Cross-Platform Support**: Works on Linux, macOS, and Windows
- **Audio & Input Streaming**: Full audio support and gamepad/controller input forwarding
- **Configurable Quality**: Customizable resolution, FPS, and bitrate settings
- **Web Interface**: Sunshine includes a modern web-based configuration UI
- **Automatic Setup**: Intelligent OS detection and dependency installation
- **Helper Scripts**: Connection info and setup guidance

## Type of Change

- [x] New module
- [ ] Bug fix
- [ ] Feature/enhancement
- [x] Documentation
- [ ] Other

## Module Information

**New Module:** `registry/coder/modules/moonlight`  
**Version:** `v1.0.0`  
**Breaking change:** [x] No

## Changes Made

### New Moonlight Module (`registry/coder/modules/moonlight/`)
- ✅ **`main.tf`** - Terraform configuration with comprehensive variable validation
- ✅ **`setup.sh.tftpl`** - Cross-platform installation and configuration script
- ✅ **`README.md`** - Detailed documentation with usage examples and troubleshooting
- ✅ **`main.test.ts`** - Comprehensive test suite with multiple scenarios

### Key Configuration Options
- **Streaming Server**: `sunshine` (default, recommended) or `gamestream` (legacy)
- **Quality Settings**: Resolution (1920x1080), FPS (60), Bitrate (20 Mbps)
- **Features**: Audio streaming, gamepad support, configurable ports
- **UI Integration**: Web interface for Sunshine, setup guides for GameStream

## Usage Examples

### Basic Sunshine Configuration (Recommended)
```terraform
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### High-Performance Configuration
```terraform
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
  
  # Quality settings for 4K workstation
  resolution = "3840x2160"
  fps = 60
  bitrate = 100
  
  # Server configuration
  streaming_server = "sunshine"
  port = 47990
}
```

### NVIDIA GameStream Configuration
```terraform
module "moonlight" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/moonlight/coder"
  version = "1.0.0"
  agent_id = coder_agent.example.id
  streaming_server = "gamestream"
}
```

## Technical Implementation

### Smart Installation Process
1. **OS Detection**: Automatically detects Linux (Debian/Ubuntu, RHEL/Fedora, Arch), macOS, Windows
2. **GPU Detection**: Identifies NVIDIA, AMD, Intel GPUs and installs appropriate drivers
3. **Dependency Management**: Installs required packages via native package managers
4. **Service Configuration**: Sets up systemd services or manual startup as appropriate
5. **Security Setup**: Configures authentication and network security

### Sunshine Server Features
- **Modern Architecture**: Open-source, actively developed, cross-platform
- **GPU Support**: NVIDIA (NVENC), AMD (VCE), Intel (QuickSync), software fallback
- **Web Interface**: https://localhost:47990 with admin panel
- **Application Streaming**: Desktop and individual applications (Steam, etc.)

### GameStream Legacy Support
- **NVIDIA GPUs**: GTX 600 series and newer (Kepler architecture)
- **GeForce Experience**: Integration with NVIDIA's official software
- **Deprecation Notice**: NVIDIA is phasing out GameStream, Sunshine recommended

## Testing & Validation

- [x] Terraform validation passes (`terraform validate`)
- [x] Module initializes successfully (`terraform init`)
- [x] Configuration syntax is valid
- [x] Template files render correctly
- [x] All tests pass (`bun test`) - 6/6 tests successful
- [x] Variable validation works correctly
- [x] Documentation examples are accurate
- [x] Cross-platform compatibility verified

## Use Cases

### 🎮 **Gaming & Entertainment**
- GPU-accelerated game streaming
- High-framerate, low-latency gaming
- Controller and gamepad support

### 🔬 **Machine Learning & AI**
- Jupyter notebook streaming with GPU visualization
- TensorFlow/PyTorch development environments
- CUDA workload streaming

### 🎨 **3D Rendering & Design**
- Blender, Maya, 3ds Max streaming
- CAD software (SolidWorks, AutoCAD)
- Video editing (Premiere, DaVinci Resolve)

### 💻 **Development Environments**
- GPU-accelerated IDE streaming
- Android development with emulator
- Game development with Unity/Unreal

## Performance Characteristics

| Quality Preset | Resolution | FPS | Bitrate | Use Case |
|---------------|------------|-----|---------|----------|
| **Office** | 1920x1080 | 30-60 | 10-15 Mbps | General productivity |
| **Development** | 2560x1440 | 60 | 25-35 Mbps | Coding, multi-monitor |
| **Gaming** | 1920x1080 | 120 | 35-50 Mbps | High-framerate gaming |
| **Workstation** | 3840x2160 | 60 | 80-100 Mbps | 4K professional work |

## Security Considerations

- **Authentication**: Web UI password protection
- **Network Security**: Configurable ports with firewall integration
- **VPN Compatibility**: Works with existing VPN solutions
- **Access Control**: User-based access management

## Backward Compatibility

This is a new module with no breaking changes to existing functionality. All configuration is opt-in.

## Related Issues

- Closes #206 - "Moonlight/GameStream remote desktop integration"
- Addresses need for GPU-accelerated remote desktop streaming
- Provides alternative to VNC-based solutions for high-performance workloads

## Files Added

- `registry/coder/modules/moonlight/main.tf` - Terraform module configuration
- `registry/coder/modules/moonlight/setup.sh.tftpl` - Installation script template
- `registry/coder/modules/moonlight/README.md` - Comprehensive documentation
- `registry/coder/modules/moonlight/main.test.ts` - Test suite

## Comparison with Existing Solutions

| Feature | Moonlight | KasmVNC | Windows RDP |
|---------|-----------|---------|-------------|
| **GPU Acceleration** | ✅ Hardware | ❌ Software | ⚠️ Limited |
| **Latency** | 🟢 Ultra-low | 🟡 Moderate | 🟡 Moderate |
| **Audio Quality** | 🟢 High-fidelity | 🟡 Basic | 🟢 Good |
| **Gaming Support** | 🟢 Excellent | ❌ Poor | 🟡 Basic |
| **Cross-Platform** | 🟢 All platforms | 🟢 Linux/web | 🔴 Windows only |
| **Setup Complexity** | 🟡 Moderate | 🟢 Simple | 🟡 Moderate |

## Future Enhancements

- Hardware encoder selection and optimization
- Advanced quality profiles and presets
- Integration with cloud GPU instances
- Multi-monitor configuration support
- Recording and streaming capabilities
