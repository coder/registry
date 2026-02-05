---
display_name: Parsec
description: Install Parsec for low-latency cloud gaming and remote desktop on Windows workspaces
icon: ../../../../.icons/parsec.svg
verified: false
tags: [windows, gaming, streaming, remote-desktop]
---

# Parsec

Enable [Parsec](https://parsec.app/) for low-latency cloud gaming and remote desktop access on Windows workspaces. Parsec provides high-performance streaming with support for 4K, 60fps, and low-latency input.

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Features

- **Low-latency streaming**: Sub-16ms latency for responsive gaming and productivity
- **High quality video**: Up to 4K resolution at 60fps
- **GPU acceleration**: Hardware encoding for smooth performance
- **Multi-monitor support**: Virtual monitors for cloud workspaces
- **Teams support**: Enterprise deployment with team computer keys

## Requirements

- Windows workspace with GPU support (recommended)
- Parsec account (free tier available)
- Parsec client installed on your local machine

## Examples

### Basic Installation

Install Parsec with default settings:

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### With Custom Hostname

Set a custom hostname for easier identification:

```tf
module "parsec" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/parsec/coder"
  version   = "1.0.0"
  agent_id  = coder_agent.main.id
  host_name = "my-gaming-workspace"
}
```

### Parsec Teams Deployment

For enterprise/team deployments with automated authentication:

```tf
module "parsec" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/parsec/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  parsec_team_id  = var.parsec_team_id
  parsec_team_key = var.parsec_team_key
}
```

### AWS Windows Template

Complete example with AWS Windows instance:

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

# Recommended: Use GPU instance types like g4dn.xlarge for best performance
```

### GCP Windows Template

Complete example with Google Cloud Windows instance:

```tf
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/parsec/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

# Recommended: Use N1 with NVIDIA T4 GPU for best performance
```

## Connecting to Your Workspace

1. **Install Parsec client** on your local machine from [parsec.app/downloads](https://parsec.app/downloads)
2. **Log in** to your Parsec account (same account as the workspace or Teams account)
3. **Find your workspace** in the Parsec computer list
4. **Click Connect** to start streaming

## Configuration Options

| Variable          | Description                                 | Default              |
| ----------------- | ------------------------------------------- | -------------------- |
| `agent_id`        | The ID of a Coder agent                     | Required             |
| `display_name`    | Display name for the Parsec app             | `"Parsec"`           |
| `slug`            | Slug for the Parsec app                     | `"parsec"`           |
| `icon`            | Icon path                                   | `"/icon/parsec.svg"` |
| `order`           | App order in UI                             | `null`               |
| `group`           | App group name                              | `null`               |
| `parsec_team_id`  | Parsec Team ID for enterprise deployments   | `""`                 |
| `parsec_team_key` | Parsec Team Computer Key for authentication | `""`                 |
| `host_name`       | Custom hostname for the Parsec host         | Workspace name       |
| `auto_start`      | Start Parsec service automatically          | `true`               |

## GPU Recommendations

For the best cloud gaming experience, use instances with dedicated GPUs:

| Cloud Provider | Recommended Instance Types |
| -------------- | -------------------------- |
| AWS            | g4dn.xlarge, g5.xlarge     |
| GCP            | n1-standard-4 + NVIDIA T4  |
| Azure          | Standard_NV6               |

## Troubleshooting

### Parsec not starting

- Ensure the workspace has GPU drivers installed
- Check Windows Event Viewer for Parsec service errors
- Verify network allows UDP traffic on ports 8000-8200

### High latency

- Use an instance in a region close to you
- Ensure hardware encoding is enabled (requires GPU)
- Check network quality between client and workspace

### Computer not appearing in Parsec

- Wait 1-2 minutes after workspace starts
- Verify Parsec service is running: `Get-Service parsec`
- Check Parsec logs in `%APPDATA%\Parsec\logs`
