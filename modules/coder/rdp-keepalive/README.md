# Windows RDP Keep Alive Module for Coder

This module extends Coder workspace sessions when active RDP connections are detected.

## Overview

The Windows RDP Keep Alive module monitors RDP connections and automatically extends workspace auto-off timers while users are actively connected via RDP, similar to how SSH connections currently work.

## Features

- **RDP Connection Detection**: Monitors active RDP sessions on Windows workspaces
- **Automatic Activity Bumping**: Extends workspace deadlines while RDP is active
- **Session Tracking**: Tracks RDP connection state to prevent premature shutdown
- **Configurable Check Interval**: Adjustable RDP polling frequency

## Usage

```hcl
module "rdp_keepalive" {
  source = "registry.coder.com/modules/rdp-keepalive/coder"
  
  # Optional: Adjust check interval (default: 60 seconds)
  check_interval = 60
  
  # Optional: Enable debug logging
  verbose = false
}
```

## Requirements

- Windows workspace with RDP enabled
- Coder agent running on the workspace
- PowerShell execution policy allowing scripts

## How It Works

1. **RDP Session Monitoring**: A background service runs on the Windows workspace, periodically checking for active RDP sessions using `qwinsta` or `query user` commands.

2. **Activity Reporting**: When an active RDP session is detected, the module reports activity to the Coder server via the agent API.

3. **Deadline Extension**: The Coder server extends the workspace auto-off deadline based on the reported activity, similar to SSH connection handling.

4. **Graceful Disconnection**: When the RDP session ends, the module stops reporting activity, allowing the normal auto-off countdown to resume.

## Technical Implementation

### Windows Service

The module installs a lightweight Windows service that:
- Runs as a background process
- Polls RDP session status every N seconds (configurable)
- Reports activity via Coder agent API
- Handles connection drops gracefully

### RDP Detection Methods

The module uses multiple methods to detect RDP sessions:
1. **qwinsta.exe**: Query Windows Station (primary method)
2. **query user**: Alternative user session query
3. **WMI/CIM**: Windows Management Instrumentation as fallback

### Activity Reporting

```powershell
# Example activity report structure
{
  "workspace_id": "...",
  "agent_id": "...",
  "connection_type": "rdp",
  "session_active": true,
  "session_count": 1,
  "timestamp": "2026-02-11T23:00:00Z"
}
```

## Installation

### Method 1: Terraform Module (Recommended)

Add to your workspace template:

```hcl
module "rdp_keepalive" {
  source = "registry.coder.com/modules/rdp-keepalive/coder"
  version = "1.0.0"
}
```

### Method 2: Manual Setup

1. Download the latest release
2. Run `install.ps1` as Administrator
3. Configure via environment variables or config file

## Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `check_interval` | RDP check interval in seconds | 60 |
| `verbose` | Enable verbose logging | false |
| `report_url` | Coder agent API endpoint | auto-detected |

## Troubleshooting

### RDP Sessions Not Detected

1. Verify RDP is enabled: `Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"`
2. Check service is running: `Get-Service CoderRDPKeepAlive`
3. Review logs: `Get-EventLog -LogName Application -Source CoderRDPKeepAlive`

### Activity Not Reported

1. Verify agent API is accessible
2. Check network connectivity to Coder server
3. Review agent token permissions

## Integration with Coder

This module integrates with Coder's existing activity bump system:

```go
// Pseudo-code for Coder server integration
type WorkspaceActivity struct {
    WorkspaceID uuid.UUID
    AgentID     uuid.UUID
    Connections ConnectionStats
}

type ConnectionStats struct {
    SSH              int64
    VSCode           int64
    JetBrains        int64
    ReconnectingPTY  int64
    RDP              int64  // New: RDP session count
}
```

## Testing

### Manual Test

1. Start a Windows workspace with this module
2. Connect via RDP
3. Verify workspace deadline is extended
4. Disconnect RDP
5. Verify normal countdown resumes

### Automated Tests

```powershell
# Run integration tests
.\tests\integration\Test-RDPKeepAlive.ps1
```

## License

MIT License - See LICENSE file

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a PR with tests
4. Include demo video showing RDP session detection and activity bumping

## References

- [Coder Activity Bump Documentation](https://coder.com/docs/workspaces#activity-bumping)
- [Windows RDP Technical Reference](https://docs.microsoft.com/en-us/windows-server/remote/remote-desktop-services/)
- Original Issue: coder/registry#200
