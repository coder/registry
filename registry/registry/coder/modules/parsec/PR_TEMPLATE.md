# Parsec Cloud Gaming Integration for Coder Workspaces

## Bounty Claim
/claim #205

## Description
This PR implements Parsec cloud gaming integration for Coder workspaces, supporting both Windows and Linux environments.

## Features
- ✅ Cross-platform support (Windows & Linux)
- ✅ Automatic Parsec installation via PowerShell (Windows) and Bash (Linux)
- ✅ Coder app integration for easy access
- ✅ Configurable port, order, and grouping
- ✅ Comprehensive documentation and examples
- ✅ Automated tests for resource validation

## Files Added
- `registry/coder/modules/parsec/main.tf` - Main Terraform module
- `registry/coder/modules/parsec/scripts/install-parsec.ps1` - Windows installation script
- `registry/coder/modules/parsec/scripts/install-parsec.sh` - Linux installation script
- `registry/coder/modules/parsec/README.md` - Documentation
- `registry/coder/modules/parsec/main.test.ts` - Automated tests
- `registry/.icons/parsec.svg` - Module icon

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
- Windows 10+ or Linux with desktop environment
- GPU support recommended for optimal performance
- Outbound internet access for Parsec download
- Parsec account for authentication

## Testing
- ✅ Terraform validation passes
- ✅ Module syntax is correct
- ✅ Cross-platform script compatibility
- ✅ Documentation is complete

## Demo Video
[Attach your demo video here showing Parsec running in a Coder workspace]

## Notes
- Parsec is free for personal use
- GPU passthrough and drivers must be configured separately
- First launch requires Parsec account login 