# Parsec Cloud Gaming Integration for Coder Workspaces

## Bounty Claim
/claim #205

## Description
This PR implements Parsec cloud gaming integration for Coder workspaces, supporting both Windows and Linux environments. Parsec provides high-performance remote desktop and cloud gaming capabilities, making it perfect for GPU-intensive development and gaming workloads in Coder workspaces.

## Features
- ✅ **Cross-platform support** (Windows & Linux)
- ✅ **Automatic Parsec installation** via PowerShell (Windows) and Bash (Linux)
- ✅ **Coder app integration** for easy access through the workspace dashboard
- ✅ **Configurable parameters** (port, order, grouping, subdomain)
- ✅ **Comprehensive documentation** with usage examples and requirements
- ✅ **Automated tests** for resource validation
- ✅ **Custom Parsec icon** for better UI integration

## Files Added
- `registry/coder/modules/parsec/main.tf` - Main Terraform module with cross-platform support
- `registry/coder/modules/parsec/scripts/install-parsec.ps1` - Windows installation script
- `registry/coder/modules/parsec/scripts/install-parsec.sh` - Linux installation script
- `registry/coder/modules/parsec/README.md` - Comprehensive documentation
- `registry/coder/modules/parsec/main.test.ts` - Automated tests for both platforms
- `registry/.icons/parsec.svg` - Custom module icon

## Usage Example
```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  os       = "windows" # or "linux"
  port     = 8000
  subdomain = true
}
```

## Requirements
- **Windows**: Windows 10+ with GPU support
- **Linux**: Desktop environment and GPU support recommended
- **Network**: Outbound internet access for Parsec download
- **Account**: Parsec account for authentication (free tier available)

## How it Works
1. **Installation**: Automatically downloads and installs Parsec on workspace startup
2. **Configuration**: Sets up Parsec with optimal settings for remote access
3. **Integration**: Exposes Parsec as a Coder app for easy access
4. **Cross-platform**: Supports both Windows and Linux with appropriate scripts

## Testing
- ✅ Terraform validation passes
- ✅ Module syntax is correct
- ✅ Cross-platform script compatibility
- ✅ Documentation is complete and follows registry standards
- ✅ Automated tests validate resource creation

## Demo Video
[Attach your demo video here showing Parsec running in a Coder workspace with successful remote connection]

## Benefits for Coder Users
- **High-performance remote desktop** for GPU-intensive workloads
- **Cloud gaming capabilities** in development environments
- **Cross-platform compatibility** for diverse workspace needs
- **Easy integration** through Coder's module system
- **Free tier available** for personal use

## Notes
- Parsec is free for personal use (see [Parsec Terms](https://parsec.app/legal/terms))
- GPU passthrough and drivers must be configured separately in the workspace template
- First launch requires Parsec account login
- For best performance, use workspaces with dedicated GPU support

## Related Links
- [Parsec Official Website](https://parsec.app/)
- [Coder Registry Documentation](https://registry.coder.com/)
- [Bounty Issue #205](https://github.com/coder/registry/issues/205) 