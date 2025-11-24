# Windows RDP Keep Alive

This module runs a background script on Windows workspaces that detects active RDP sessions and prevents the workspace from shutting down due to inactivity.

## Usage

```hcl
module "rdp_keepalive" {
  source   = "[registry.coder.com/modules/windows-rdp-keepalive/coder](https://registry.coder.com/modules/windows-rdp-keepalive/coder)"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}