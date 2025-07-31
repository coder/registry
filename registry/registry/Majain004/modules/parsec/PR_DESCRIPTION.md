# Parsec Cloud Gaming Integration for Coder Workspaces

## Overview

This PR implements Parsec cloud gaming integration for Coder workspaces, supporting both Windows and Linux environments. Parsec provides high-performance remote desktop and cloud gaming capabilities, making it perfect for GPU-intensive development and gaming workloads in Coder workspaces.

## Features

- ✅ **Cross-platform support** - Windows and Linux compatibility
- ✅ **Automatic installation** - PowerShell (Windows) and Bash (Linux) scripts
- ✅ **Coder app integration** - Exposes Parsec as a Coder app for easy access
- ✅ **Custom icon** - Professional Parsec branding
- ✅ **Comprehensive testing** - Full test coverage for both platforms

## Files Added

- `registry/Majain004/modules/parsec/main.tf` - Main Terraform module with cross-platform support
- `registry/Majain004/modules/parsec/scripts/install-parsec.ps1` - Windows installation script
- `registry/Majain004/modules/parsec/scripts/install-parsec.sh` - Linux installation script
- `registry/Majain004/modules/parsec/README.md` - Comprehensive documentation
- `registry/Majain004/modules/parsec/main.test.ts` - Automated tests for both platforms
- `registry/Majain004/modules/parsec/.terraform.lock.hcl` - Provider version lock

## Usage

```tf
module "parsec" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/Majain004/parsec/coder"
  version    = "1.0.0"
  agent_id   = resource.coder_agent.main.id
  os         = "windows" # or "linux"
  port       = 8000
  subdomain  = true
}
```

## Requirements

- **Network**: Outbound internet access for Parsec download
- **Account**: Parsec account for authentication (free tier available)
- **Hardware**: GPU support recommended for best performance

## How it Works

1. **Installation**: Automatically downloads and installs Parsec on workspace startup
2. **Configuration**: Sets up Parsec with optimal settings for remote access
3. **Integration**: Exposes Parsec as a Coder app for easy access

## Testing

All tests pass successfully, covering:
- Windows and Linux installation scenarios
- Custom port configuration
- Subdomain settings
- Resource creation validation

## Video Demonstration

[Attach your demo video here showing Parsec running in a Coder workspace with successful remote connection]

## Notes

- Parsec is free for personal use (see [Parsec Terms](https://parsec.app/legal/terms))
- First launch requires Parsec account login
- GPU acceleration recommended for optimal performance
- Compatible with Coder's workspace architecture

## References

- [Parsec Official Website](https://parsec.app/)
- [Parsec Documentation](https://parsec.app/docs)
- [Coder Module Guidelines](CONTRIBUTING.md) 