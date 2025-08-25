---
display_name: AWS AMI Snapshot
description: Create and manage AMI snapshots for Coder workspaces with restore capabilities
icon: ../../../../.icons/aws.svg
verified: false
tags: [aws, snapshot, ami, backup, persistence]
---

# AWS AMI Snapshot Module

This module provides AMI-based snapshot functionality for Coder workspaces running on AWS EC2 instances. It enables users to create snapshots when workspaces are stopped and restore from previous snapshots when starting workspaces.

```tf
module "ami_snapshot" {
  source  = "registry.coder.com/mavrickrishi/aws-ami-snapshot/coder"
  version = "1.0.0"

  instance_id    = aws_instance.workspace.id
  default_ami_id = data.aws_ami.ubuntu.id
  template_name  = "aws-linux"
}
```

## Features

- **Automatic Snapshots**: Create AMI snapshots when workspaces are stopped
- **User Control**: Enable/disable snapshot functionality per workspace
- **Custom Labels**: Add custom labels to snapshots for easy identification
- **Snapshot Selection**: Choose from available snapshots when starting workspaces
- **Automatic Cleanup**: Optional Data Lifecycle Manager integration for automated cleanup
- **Workspace Isolation**: Snapshots are tagged and filtered by workspace and owner

## Parameters

The module exposes the following parameters to workspace users:

- `enable_snapshots`: Enable/disable AMI snapshot creation (default: true)
- `snapshot_label`: Custom label for the snapshot (optional)
- `use_previous_snapshot`: Select a previous snapshot to restore from (default: none)

## Usage

### Basic Usage

```hcl
module "ami_snapshot" {
  source = "registry.coder.com/modules/aws-ami-snapshot"

  instance_id     = aws_instance.workspace.id
  default_ami_id  = data.aws_ami.ubuntu.id
  template_name   = "aws-linux"
}

resource "aws_instance" "workspace" {
  ami           = module.ami_snapshot.ami_id
  instance_type = "t3.micro"

  # Prevent Terraform from recreating instance when AMI changes
  lifecycle {
    ignore_changes = [ami]
  }
}
```

### With Optional Cleanup

```hcl
module "ami_snapshot" {
  source = "registry.coder.com/modules/aws-ami-snapshot"

  instance_id               = aws_instance.workspace.id
  default_ami_id           = data.aws_ami.ubuntu.id
  template_name            = "aws-linux"
  enable_dlm_cleanup       = true
  dlm_role_arn            = aws_iam_role.dlm_lifecycle_role.arn
  snapshot_retention_count = 5

  tags = {
    Environment = "development"
    Project     = "my-project"
  }
}
```

### IAM Role for DLM (Optional)

If using automatic cleanup, create an IAM role for Data Lifecycle Manager:

```hcl
resource "aws_iam_role" "dlm_lifecycle_role" {
  name = "dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dlm_lifecycle" {
  role       = aws_iam_role.dlm_lifecycle_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}
```

## Required IAM Permissions

Users need the following IAM permissions for full functionality:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:CreateTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dlm:CreateLifecyclePolicy",
        "dlm:GetLifecyclePolicy",
        "dlm:UpdateLifecyclePolicy",
        "dlm:DeleteLifecyclePolicy"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "dlm:Target": "INSTANCE"
        }
      }
    }
  ]
}
```

## How It Works

1. **Snapshot Creation**: When a workspace transitions to "stop", an AMI snapshot is automatically created (if enabled)
2. **Tagging**: Snapshots are tagged with workspace name, owner, template, and custom labels
3. **Snapshot Retrieval**: Available snapshots are retrieved and presented as options for workspace start
4. **AMI Selection**: The module outputs the appropriate AMI ID (default or selected snapshot)
5. **Cleanup**: Optional DLM policies can automatically clean up old snapshots

## Considerations

- **Cost**: AMI snapshots incur storage costs. Use cleanup policies to manage costs
- **Time**: AMI creation takes time; workspace stop operations may take longer
- **Permissions**: Ensure proper IAM permissions for AMI creation and management
- **Region**: Snapshots are region-specific and cannot be used across regions
- **Lifecycle**: Use `ignore_changes = [ami]` on EC2 instances to prevent conflicts

## Examples

See the updated AWS templates that use this module:

- [`coder/templates/aws-linux`](https://registry.coder.com/templates/aws-linux)
- [`coder/templates/aws-windows`](https://registry.coder.com/templates/aws-windows)
- [`coder/templates/aws-devcontainer`](https://registry.coder.com/templates/aws-devcontainer)
