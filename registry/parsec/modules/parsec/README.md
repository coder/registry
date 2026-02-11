# Parsec Module for Coder

Integrate [Parsec](https://parsec.app/) cloud gaming and remote desktop into your Coder workspaces.

## Features

- 🎮 Low-latency remote desktop and cloud gaming
- 🚀 Automatic installation and configuration
- 🔒 Secure access through Coder's authentication
- 💻 Support for Ubuntu, Debian, Fedora, and RHEL-based distributions
- 🌐 Web-based interface

## Requirements

- **Operating System**: Ubuntu 18.04+, Debian, Fedora, RHEL, CentOS, Rocky Linux, or AlmaLinux
- **Architecture**: x86_64 (amd64) only
- **Sudo Access**: NOPASSWD sudo required for installation
- **Desktop Environment**: A desktop environment must be installed (GNOME, KDE, XFCE, etc.)

## Usage

```hcl
module "parsec" {
  source   = "registry.coder.com/modules/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### With Custom Port

```hcl
module "parsec" {
  source   = "registry.coder.com/modules/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  port     = 8080
}
```

### With Custom Order and Group

```hcl
module "parsec" {
  source   = "registry.coder.com/modules/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  order    = 1
  group    = "Remote Desktop"
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `agent_id` | The ID of a Coder agent | `string` | - | yes |
| `port` | The port to run Parsec web interface on | `number` | `8000` | no |
| `order` | The order determines the position of app in the UI presentation | `number` | `null` | no |
| `group` | The name of a group that this app belongs to | `string` | `null` | no |
| `subdomain` | Is subdomain sharing enabled in your cluster? | `bool` | `true` | no |

## Authentication

Parsec requires authentication to use. After the module starts:

1. Click on the Parsec app in your Coder workspace
2. You'll be redirected to the Parsec web interface
3. Log in with your Parsec account or create a new one
4. Once authenticated, you can start using Parsec for remote desktop or gaming

## How It Works

1. **Installation**: The module automatically detects your Linux distribution and installs the appropriate Parsec package (.deb or .rpm)
2. **Configuration**: Parsec daemon is configured to run on the specified port
3. **Startup**: The Parsec daemon starts automatically when your workspace starts
4. **Access**: Access Parsec through the Coder web interface

## Supported Distributions

- **Debian-based**: Ubuntu 18.04+, Debian, Kali Linux, Pop!_OS, Linux Mint
- **RPM-based**: Fedora, RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux

## Troubleshooting

### Parsec won't start

- Ensure you have a desktop environment installed
- Check that sudo NOPASSWD access is configured
- Verify your architecture is x86_64

### Authentication issues

- Make sure you have a Parsec account (free at https://parsec.app/)
- Try logging in through the web interface
- Check Parsec logs: `journalctl -u parsecd`

### Performance issues

- Ensure your workspace has sufficient resources (CPU, RAM, GPU if available)
- Check network latency between client and server
- Consider using a workspace with GPU support for gaming

## Resources

- [Parsec Official Website](https://parsec.app/)
- [Parsec Documentation](https://support.parsec.app/)
- [Parsec System Requirements](https://support.parsec.app/hc/en-us/articles/4425688194189)

## License

This module is provided as-is for use with Coder workspaces.
