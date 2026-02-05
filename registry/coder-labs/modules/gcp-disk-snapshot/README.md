---
display_name: GCP Disk Snapshot
description: Create and manage disk snapshots for Coder workspaces on GCP with automatic cleanup
icon: ../../../../.icons/gcp.svg
verified: false
tags: [gcp, snapshot, disk, backup, persistence]
---

# GCP Disk Snapshot Module

This module provides disk snapshot functionality for Coder workspaces running on GCP Compute Engine. It automatically creates snapshots when workspaces are stopped and allows users to restore from previous snapshots when starting workspaces.

```tf
module "disk_snapshot" {
  source  = "registry.coder.com/coder-labs/gcp-disk-snapshot/coder"
  version = "1.0.0"

  disk_self_link = google_compute_disk.workspace.self_link
  default_image  = "debian-cloud/debian-12"
  zone           = var.zone
  project        = var.project_id
}
```

## Features

- **Automatic Snapshots**: Creates disk snapshots when workspaces are stopped
- **Automatic Cleanup**: Maintains only the N most recent snapshots (configurable)
- **Snapshot Selection**: Users can choose from available snapshots when starting workspaces
- **Default to Newest**: Automatically selects the most recent snapshot by default
- **Workspace Isolation**: Snapshots are labeled and filtered by workspace and owner

## Usage

### Basic Usage

```hcl
module "disk_snapshot" {
  source = "registry.coder.com/coder-labs/gcp-disk-snapshot/coder"

  disk_self_link = google_compute_disk.workspace.self_link
  default_image  = "debian-cloud/debian-12"
  zone           = var.zone
  project        = var.project_id
}

# Create disk from snapshot or default image
resource "google_compute_disk" "workspace" {
  name    = "workspace-${data.coder_workspace.me.id}"
  type    = "pd-balanced"
  zone    = var.zone
  size    = 50
  
  # Use snapshot if available, otherwise use default image
  snapshot = module.disk_snapshot.snapshot_self_link
  image    = module.disk_snapshot.use_snapshot ? null : module.disk_snapshot.default_image

  lifecycle {
    ignore_changes = [snapshot, image]
  }
}
```

### With Custom Retention

```hcl
module "disk_snapshot" {
  source = "registry.coder.com/coder-labs/gcp-disk-snapshot/coder"

  disk_self_link           = google_compute_disk.workspace.self_link
  default_image            = "debian-cloud/debian-12"
  zone                     = var.zone
  project                  = var.project_id
  snapshot_retention_count = 5  # Keep last 5 snapshots

  labels = {
    environment = "development"
    team        = "engineering"
  }
}
```

### With Regional Storage

```hcl
module "disk_snapshot" {
  source = "registry.coder.com/coder-labs/gcp-disk-snapshot/coder"

  disk_self_link    = google_compute_disk.workspace.self_link
  default_image     = "debian-cloud/debian-12"
  zone              = var.zone
  project           = var.project_id
  storage_locations = ["us-central1"]  # Store snapshots in specific region
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| disk_self_link | The self_link of the disk to create snapshots from | string | - | yes |
| default_image | The default image to use when not restoring from a snapshot | string | - | yes |
| zone | The zone where the disk resides | string | - | yes |
| project | The GCP project ID | string | - | yes |
| snapshot_retention_count | Number of snapshots to retain | number | 3 | no |
| storage_locations | Cloud Storage bucket location(s) for snapshots | list(string) | [] | no |
| labels | Additional labels to apply to snapshots | map(string) | {} | no |
| test_mode | Skip GCP API calls for testing | bool | false | no |

## Outputs

| Name | Description |
|------|-------------|
| snapshot_self_link | Self link of the selected snapshot (null if using fresh disk) |
| use_snapshot | Whether a snapshot is being used |
| default_image | The default image configured |
| selected_snapshot_name | Name of the selected snapshot |
| available_snapshots | List of available snapshot names |
| created_snapshot_name | Name of snapshot created on stop |

## Required IAM Permissions

The service account running Terraform needs the following permissions:

```json
{
  "permissions": [
    "compute.snapshots.create",
    "compute.snapshots.delete",
    "compute.snapshots.get",
    "compute.snapshots.list",
    "compute.snapshots.setLabels",
    "compute.disks.createSnapshot"
  ]
}
```

Or use the predefined role: `roles/compute.storageAdmin`

## How It Works

1. **Snapshot Creation**: When a workspace transitions to "stop", a disk snapshot is automatically created
2. **Labeling**: Snapshots are labeled with workspace name, owner, and template for filtering
3. **Cleanup**: Old snapshots beyond the retention count are automatically deleted
4. **Restore Selection**: Available snapshots are presented as options, defaulting to the newest
5. **Disk Creation**: The module outputs are used to create a disk from snapshot or default image

## Considerations

- **Cost**: Snapshots incur storage costs. The retention policy helps manage costs
- **Time**: Snapshot creation takes time; workspace stop operations may take longer
- **Permissions**: Ensure proper IAM permissions for snapshot management
- **Region**: Snapshots can be stored regionally for cost optimization
- **Lifecycle**: Use `ignore_changes = [snapshot, image]` on disks to prevent Terraform conflicts

## Comparison with Machine Images

This module uses *disk snapshots* rather than *machine images*:

| Feature | Disk Snapshots | Machine Images |
|---------|---------------|----------------|
| API Status | GA (stable) | Beta |
| Captures | Disk data only | Full instance config + disks |
| Cleanup | Automatic via retention policy | Manual or custom automation |
| Cost | Lower | Higher |
| Restore | Requires instance config | Full instance restore |

For most Coder workspace use cases, disk snapshots are recommended as they capture the persistent data while the instance configuration is managed by Terraform.
