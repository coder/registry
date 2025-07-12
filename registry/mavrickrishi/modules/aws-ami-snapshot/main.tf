terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

# Variables
variable "instance_id" {
  description = "The EC2 instance ID to create snapshots from"
  type        = string
}

variable "default_ami_id" {
  description = "The default AMI ID to use when not restoring from a snapshot"
  type        = string
}

variable "template_name" {
  description = "The name of the Coder template using this module"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to snapshots"
  type        = map(string)
  default     = {}
}

variable "enable_dlm_cleanup" {
  description = "Enable Data Lifecycle Manager for automated snapshot cleanup"
  type        = bool
  default     = false
}

variable "dlm_role_arn" {
  description = "ARN of the IAM role for DLM (required if enable_dlm_cleanup is true)"
  type        = string
  default     = ""
}

variable "snapshot_retention_count" {
  description = "Number of snapshots to retain when using DLM cleanup"
  type        = number
  default     = 7
}

# Parameters for snapshot control
data "coder_parameter" "enable_snapshots" {
  name         = "enable_snapshots"
  display_name = "Enable AMI Snapshots"
  description  = "Create AMI snapshots when workspace is stopped"
  type         = "bool"
  default      = "true"
  mutable      = true
}

data "coder_parameter" "snapshot_label" {
  name         = "snapshot_label"
  display_name = "Snapshot Label"
  description  = "Custom label for this snapshot (optional)"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "use_previous_snapshot" {
  name         = "use_previous_snapshot"
  display_name = "Start from Snapshot"
  description  = "Select a previous snapshot to restore from"
  type         = "string"
  default      = "none"
  mutable      = true
  option {
    name        = "Use default AMI"
    value       = "none"
    description = "Start with a fresh instance"
  }
  dynamic "option" {
    for_each = data.aws_ami_ids.workspace_snapshots.ids
    content {
      name        = "${data.aws_ami.snapshot_info[option.value].name} (${formatdate("YYYY-MM-DD hh:mm", data.aws_ami.snapshot_info[option.value].creation_date)})"
      value       = option.value
      description = data.aws_ami.snapshot_info[option.value].description
    }
  }
}

# Get workspace information
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Retrieve existing snapshots for this workspace
data "aws_ami_ids" "workspace_snapshots" {
  owners = ["self"]

  filter {
    name   = "tag:CoderWorkspace"
    values = [data.coder_workspace.me.name]
  }

  filter {
    name   = "tag:CoderOwner"
    values = [data.coder_workspace_owner.me.name]
  }

  filter {
    name   = "tag:CoderTemplate"
    values = [var.template_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get detailed information about each snapshot
data "aws_ami" "snapshot_info" {
  for_each = toset(data.aws_ami_ids.workspace_snapshots.ids)
  owners   = ["self"]

  filter {
    name   = "image-id"
    values = [each.value]
  }
}

# Determine which AMI to use
locals {
  use_snapshot = data.coder_parameter.use_previous_snapshot.value != "none"
  ami_id       = local.use_snapshot ? data.coder_parameter.use_previous_snapshot.value : var.default_ami_id
}

# Create AMI snapshot when workspace is stopped
resource "aws_ami_from_instance" "workspace_snapshot" {
  count                   = data.coder_parameter.enable_snapshots.value && data.coder_workspace.me.transition == "stop" ? 1 : 0
  name                    = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  source_instance_id      = var.instance_id
  snapshot_without_reboot = true
  deprecation_time        = timeadd(timestamp(), "168h") # 7 days

  tags = merge(var.tags, {
    Name           = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-snapshot"
    CoderWorkspace = data.coder_workspace.me.name
    CoderOwner     = data.coder_workspace_owner.me.name
    CoderTemplate  = var.template_name
    SnapshotLabel  = data.coder_parameter.snapshot_label.value
    CreatedAt      = timestamp()
    SnapshotType   = "workspace"
    WorkspaceId    = data.coder_workspace.me.id
  })

  lifecycle {
    ignore_changes = [
      deprecation_time
    ]
  }
}

# Optional: Data Lifecycle Manager policy for automated cleanup
resource "aws_dlm_lifecycle_policy" "workspace_snapshots" {
  count              = var.enable_dlm_cleanup ? 1 : 0
  description        = "Lifecycle policy for Coder workspace AMI snapshots"
  execution_role_arn = var.dlm_role_arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["INSTANCE"]
    target_tags = {
      CoderTemplate = var.template_name
      SnapshotType  = "workspace"
    }

    schedule {
      name = "Coder workspace snapshot cleanup"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      copy_tags = true
    }
  }
}

# Outputs
output "ami_id" {
  description = "The AMI ID to use for the workspace instance (either default or selected snapshot)"
  value       = local.ami_id
}

output "is_using_snapshot" {
  description = "Whether the workspace is using a snapshot AMI"
  value       = local.use_snapshot
}

output "snapshot_ami_id" {
  description = "The AMI ID of the created snapshot (if any)"
  value       = data.coder_parameter.enable_snapshots.value && data.coder_workspace.me.transition == "stop" ? aws_ami_from_instance.workspace_snapshot[0].id : null
}

output "available_snapshots" {
  description = "List of available snapshot AMI IDs for this workspace"
  value       = data.aws_ami_ids.workspace_snapshots.ids
}

output "snapshot_info" {
  description = "Detailed information about available snapshots"
  value = {
    for ami_id in data.aws_ami_ids.workspace_snapshots.ids : ami_id => {
      name         = data.aws_ami.snapshot_info[ami_id].name
      description  = data.aws_ami.snapshot_info[ami_id].description
      created_date = data.aws_ami.snapshot_info[ami_id].creation_date
      tags         = data.aws_ami.snapshot_info[ami_id].tags
    }
  }
}