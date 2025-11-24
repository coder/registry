# Windows RDP Keep Alive Module

**Status:** Beta (Tested on Windows Server)

This module adds a background process designed to keep Windows Coder workspaces active during RDP sessions.

When an RDP session is active, the Coder agent may trigger an inactivity shutdown based on low CPU/network use. This module prevents shutdown by injecting a background PowerShell loop (`coder_script`).

The script monitors commands (`query user` or similar) to detect active RDP sessions (`rdp-tcp` in `Active` state). When detected, it generates standard output to simulate activity, resetting the Coder agent's idleness timer.

## Variables

| Name       | Description                                       | Default |
| ---------- | ------------------------------------------------- | ------- |
| `interval` | Interval in seconds to check for RDP connections. | `60`    |

## Usage Example

```hcl
module "windows_rdp_keepalive" {
  source  = "[https://registry.coder.com/modules/windows-rdp-keepalive](https://registry.coder.com/modules/windows-rdp-keepalive)"
  agent_id = coder_agent.main.id
  interval = 300 # Check every 5 minutes
}
```
