---
display_name: GCP Disk Snapshot
description: Create and manage disk snapshots for Coder workspaces on GCP with automatic rotation
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
- **Rotating Slots**: Maintains up to N snapshot slots (configurable, default: 3)
- **Snapshot Selection**: Users can choose from available snapshots when starting workspaces
- **Default to Newest**: Automatically selects the most recent snapshot by default
- **Pure Terraform**: No external CLI dependencies (gcloud not required)
- **Workspace Isolation**: Snapshots are labeled and filtered by workspace and owner

## How It Works

The module uses a **rotating slot** approach:

1. Snapshots are named with predictable slot names: `{owner}-{workspace}-slot-1`, `slot-2`, `slot-3`
2. When a workspace stops, a new snapshot is created in the next available slot
3. Once all slots are full, the oldest slot is reused (round-robin)
4. Users can select from any available snapshot when starting the workspace
5. By default, the most recent snapshot is selected

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
  name = "workspace-${data.coder_workspace.me.id}"
  type = "pd-balanced"
  zone = var.zone
  size = 50

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
  snapshot_retention_count = 2 # Keep only 2 snapshot slots

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
  storage_locations = ["us-central1"] # Store snapshots in specific region
}
```

## Variables

| Name                     | Description                                                 | Type         | Default | Required |
| ------------------------ | ----------------------------------------------------------- | ------------ | ------- | :------: |
| disk_self_link           | The self_link of the disk to create snapshots from          | string       | -       |   yes    |
| default_image            | The default image to use when not restoring from a snapshot | string       | -       |   yes    |
| zone                     | The zone where the disk resides                             | string       | -       |   yes    |
| project                  | The GCP project ID                                          | string       | -       |   yes    |
| snapshot_retention_count | Number of snapshot slots to maintain (1-3)                  | number       | 3       |    no    |
| storage_locations        | Cloud Storage bucket location(s) for snapshots              | list(string) | []      |    no    |
| labels                   | Additional labels to apply to snapshots                     | map(string)  | {}      |    no    |
| test_mode                | Skip GCP API calls for testing                              | bool         | false   |    no    |

## Outputs

| Name                   | Description                                             |
| ---------------------- | ------------------------------------------------------- |
| snapshot_self_link     | Self link of the selected snapshot (null if fresh disk) |
| use_snapshot           | Whether a snapshot is being used                        |
| default_image          | The default image configured                            |
| selected_snapshot_name | Name of the selected snapshot                           |
| available_snapshots    | List of available snapshot names                        |
| created_snapshot_name  | Name of snapshot created on stop                        |
| snapshot_slots         | The snapshot slot names used for rotation               |

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

## Considerations

- **Cost**: Snapshots incur storage costs. The rotating slot approach limits the number of snapshots.
- **Slot Naming**: Snapshots use predictable names (`-slot-1`, `-slot-2`, etc.) for rotation
- **Time**: Snapshot creation takes time; workspace stop operations may take longer
- **Permissions**: Ensure proper IAM permissions for snapshot management
- **Region**: Snapshots can be stored regionally for cost optimization
- **Lifecycle**: Use `ignore_changes = [snapshot, image]` on disks to prevent Terraform conflicts

## Comparison with Machine Images

This module uses _disk snapshots_ rather than _machine images_:

| Feature     | Disk Snapshots           | Machine Images               |
| ----------- | ------------------------ | ---------------------------- |
| API Status  | GA (stable)              | Beta                         |
| Captures    | Disk data only           | Full instance config + disks |
| Cleanup     | Rotating slots (simple)  | Manual or custom automation  |
| Cost        | Lower                    | Higher                       |
| Restore     | Requires instance config | Full instance restore        |
| List/Filter | Limited in Terraform     | Limited in Terraform         |

For most Coder workspace use cases, disk snapshots are recommended as they capture the persistent data while the instance configuration is managed by Terraform.
