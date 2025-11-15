---
display_name: AWS CLI
description: Install the AWS Command Line Interface in your workspace
icon: ../../../../.icons/aws.svg
verified: false
tags: [aws, cli, tools]
---

# AWS CLI

Automatically install the [AWS Command Line Interface (CLI)](https://aws.amazon.com/cli/) in a Coder workspace. The AWS CLI is a unified tool to manage AWS services from the command line.

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/ausbru87/aws-cli"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- ✅ Supports both x86_64 and ARM64 (aarch64) architectures
- ✅ Automatic architecture detection
- ✅ Install latest version or pin to a specific version
- ✅ Optional GPG signature verification
- ✅ Idempotent - skips installation if already present
- ✅ Supports custom installation directories

## Examples

### Basic Installation (Latest Version)

Install the latest version of AWS CLI:

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/ausbru87/aws-cli"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Pin to Specific Version

Install a specific version of AWS CLI for consistency across your team:

```tf
module "aws-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/ausbru87/aws-cli"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  # Pin to AWS CLI version 2.15.0
  aws_cli_version = "2.15.0"
}
```

Note: Find available versions in the [AWS CLI v2 Changelog](https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst).

### Custom Installation Directory

Install AWS CLI to a custom directory (useful when you don't have sudo access):

```tf
module "aws-cli" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/modules/ausbru87/aws-cli"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  install_directory  = "/home/coder/.local"
}
```

### Verify GPG Signature

Enable GPG signature verification for enhanced security:

```tf
module "aws-cli" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/modules/ausbru87/aws-cli"
  version          = "1.0.0"
  agent_id         = coder_agent.example.id
  verify_signature = true
}
```

### Specify Architecture

Explicitly set the architecture (usually auto-detected):

```tf
module "aws-cli" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/modules/ausbru87/aws-cli"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  architecture = "aarch64"  # or "x86_64"
}
```

## Configuration

After installing AWS CLI, users will need to configure their AWS credentials. This can be done using:

```bash
aws configure
```

Or by setting environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="us-east-1"
```

For more information, see the [AWS CLI Configuration Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html).

## Variables

| Name                | Description                                                                                  | Default        | Required |
| ------------------- | -------------------------------------------------------------------------------------------- | -------------- | -------- |
| `agent_id`          | The ID of a Coder agent                                                                      | -              | Yes      |
| `aws_cli_version`   | The version of AWS CLI to install (leave empty for latest)                                   | `""`           | No       |
| `install_directory` | The directory to install AWS CLI to                                                          | `/usr/local`   | No       |
| `architecture`      | The architecture to install AWS CLI for (`x86_64` or `aarch64`, empty for auto-detection)    | `""`           | No       |
| `verify_signature`  | Whether to verify the GPG signature of the downloaded installer                              | `false`        | No       |

## Outputs

| Name              | Description                                                                          |
| ----------------- | ------------------------------------------------------------------------------------ |
| `aws_cli_version` | The version of AWS CLI that was installed (or 'latest' if no version was specified) |

## Requirements

- Linux operating system (x86_64 or ARM64)
- `curl` for downloading the installer
- `unzip` for extracting the installer
- `sudo` access (if installing to system directories like `/usr/local`)
- Optional: `gpg` (if using signature verification)

## Supported Platforms

- Amazon Linux 1 & 2
- CentOS
- Fedora
- Ubuntu
- Debian
- Any Linux distribution with glibc, groff, and less

## Notes

- The module is idempotent - if AWS CLI is already installed with the correct version, it will skip the installation
- When no version is specified, the latest version will be installed
- The installer automatically creates a symlink at `/usr/local/bin/aws` (or `$INSTALL_DIRECTORY/bin/aws`)
- Architecture is automatically detected based on `uname -m` if not explicitly specified
