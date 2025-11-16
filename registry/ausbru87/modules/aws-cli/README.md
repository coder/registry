---
display_name: AWS CLI
description: Install AWS CLI v2 in your workspace
icon: ../../../../.icons/aws.svg
verified: false
tags: [helper, aws, cli]
---

# AWS CLI

Automatically install the [AWS CLI v2](https://aws.amazon.com/cli/) in your Coder workspace.

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/ausbru87/aws-cli/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

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
