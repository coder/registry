---
display_name: Parsec
description: Low-latency cloud gaming remote desktop access for workspaces
icon: ../../../../.icons/desktop.svg
verified: true
tags: [remote-desktop, gaming, parsec, desktop, low-latency]
---

# Parsec

Add low-latency remote desktop access to your Coder workspaces using [Parsec](https://parsec.app/), the cloud gaming platform. Parsec provides near-zero latency remote desktop streaming, making it ideal for graphics-intensive applications, gaming, and high-performance computing workloads.

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Features

- **Low-latency streaming**: Sub-1ms latency for responsive remote desktop access
- **Cross-platform support**: Works with Windows, macOS, Linux, and web clients
- **Automatic installation**: Handles Parsec server installation and configuration
- **Headless operation**: Optimized for server environments
- **Customizable IDs**: Set custom server and peer IDs for identification
- **Systemd integration**: Automatic service management on systemd systems

## Requirements

- **Supported OS**: Ubuntu/Debian, CentOS/RHEL/Fedora
- **Architecture**: x86_64, ARM64
- **Network**: Stable internet connection for low-latency streaming
- **Permissions**: sudo access required for installation

## Examples

### Basic Setup

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### Custom Configuration

```tf
module "parsec" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/parsec/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  parsec_version = "150_39b"  # Specific Parsec version
  server_id      = "my-workspace-server"
  peer_id        = "workspace-peer-001"
  share          = "authenticated"  # Allow authenticated users to access
  order          = 1
}
```

### With AWS

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

# AWS EC2 instance with GPU support (recommended for gaming/graphics)
resource "aws_instance" "workspace" {
  ami           = "ami-0abcdef1234567890"  # Ubuntu with NVIDIA drivers
  instance_type = "g4dn.xlarge"           # GPU instance
  # ... other configuration
}
```

### With Google Cloud

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

# GCP instance with GPU
resource "google_compute_instance" "workspace" {
  name         = "coder-workspace"
  machine_type = "n1-standard-8"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  # GPU configuration
  guest_accelerator {
    type  = "nvidia-tesla-t4"
    count = 1
  }
  # ... other configuration
}
```

## Configuration Options

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | `string` | - | **Required.** The ID of a Coder agent |
| `order` | `number` | `null` | UI position order |
| `group` | `string` | `null` | App group name |
| `share` | `string` | `"owner"` | Sharing level: `owner`, `authenticated`, `public` |
| `parsec_version` | `string` | `"latest"` | Parsec version to install |
| `server_id` | `string` | `""` | Custom server ID |
| `peer_id` | `string` | `""` | Custom peer ID |

## Usage

1. **Install the Parsec client** on your local machine from [parsec.app](https://parsec.app/)
2. **Add the module** to your Coder template
3. **Start your workspace** - Parsec will be automatically installed and configured
4. **Connect using the Parsec app**:
   - Open the Parsec client
   - Look for your workspace in the host list
   - Click to connect with ultra-low latency

## Troubleshooting

### Connection Issues
- Ensure your workspace has a stable internet connection
- Check that Parsec is running: `systemctl status parsec` (on systemd systems)
- Verify firewall settings allow Parsec traffic

### Performance Issues
- For best performance, use instances with GPU support
- Ensure adequate bandwidth (minimum 10 Mbps recommended)
- Close unnecessary applications on the workspace

### Installation Issues
- The module requires sudo access for Parsec installation
- Supported distributions: Ubuntu/Debian, CentOS/RHEL/Fedora
- Check system logs: `journalctl -u parsec` (systemd) or `/tmp/parsec.log`

## Security Considerations

- By default, Parsec access is restricted to the workspace owner
- Use `share = "authenticated"` to allow all authenticated Coder users
- Consider network security groups/firewalls to restrict access
- Parsec uses end-to-end encryption for all connections

## Advanced Configuration

The module creates a Parsec configuration file at `~/.parsec/config.txt` with optimized settings for headless operation. You can modify this file after installation for advanced tuning.

For more information about Parsec configuration options, visit the [Parsec documentation](https://support.parsec.app/hc/en-us).
