---
display_name: AWS CLI
description: Install AWS CLI v2 in your workspace
icon: ../../../../.icons/aws.svg
verified: false
tags: [helper, aws, cli]
---

# AWS CLI

Automatically install the [AWS CLI v2](https://aws.amazon.com/cli/) in your Coder workspace with command autocomplete support for bash, zsh, and fish shells.

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/ausbru87/aws-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- Installs AWS CLI v2 for Linux and macOS
- Supports x86_64 and ARM64 architectures
- Optional version pinning
- **Auto-configures command autocomplete** for bash, zsh, and fish shells

## Examples

### Basic Installation

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/ausbru87/aws-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Pin to Specific Version

```tf
module "aws-cli" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/ausbru87/aws-cli/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.example.id
  install_version = "2.15.0"
}
```

### Custom Log Path

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/ausbru87/aws-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  log_path = "/var/log/aws-cli.log"
}
```

### Airgapped Environment

Use a custom download URL for environments without internet access to AWS:

```tf
module "aws-cli" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/ausbru87/aws-cli/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  download_url = "https://internal-mirror.company.com/awscli-exe-linux-x86_64.zip"
}
```
