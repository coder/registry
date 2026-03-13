---
display_name: GCP Disk Snapshot
description: Create and manage disk snapshots for Coder workspaces on GCP
icon: ../../../../.icons/gcp.svg
verified: false
tags: [gcp, snapshot, disk, backup, persistence]
---

# GCP Disk Snapshot Module

This module provides disk snapshot functionality for Coder workspaces running on GCP Compute Engine. It automatically creates a snapshot when workspaces are stopped and allows users to restore from the snapshot when starting.

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

- **Automatic Snapshots**: Creates a disk snapshot when workspaces are stopped
- **Single Snapshot**: Maintains one snapshot per workspace (overwrites on each stop)
- **Restore Option**: Users can choose to restore from snapshot or start fresh
- **Default to Restore**: Automatically selects restore if a snapshot exists
- **Pure Terraform**: No external CLI dependencies
- **Workspace Isolation**: Snapshots are named and labeled by workspace and owner

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

### With Regional Storage

```hcl
module "disk_snapshot" {
  source = "registry.coder.com/coder-labs/gcp-disk-snapshot/coder"

  disk_self_link    = google_compute_disk.workspace.self_link
  default_image     = "debian-cloud/debian-12"
  zone              = var.zone
  project           = var.project_id
  storage_locations = ["us-central1"] # Store snapshot in specific region

  labels = {
    environment = "development"
    team        = "engineering"
  }
}
```

## How It Works

1. When a workspace stops, a snapshot is created with a predictable name: `{owner}-{workspace}-snapshot`
2. The snapshot is overwritten each time the workspace stops
3. When starting, users can choose to restore from the snapshot or start fresh
4. If a snapshot exists, restore is selected by default

## Required IAM Permissions

The service account running Terraform needs:

- `compute.snapshots.create`
- `compute.snapshots.delete`
- `compute.snapshots.get`
- `compute.disks.createSnapshot`

Or use the predefined role: `roles/compute.storageAdmin`
