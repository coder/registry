terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
  }
}

# Provider configuration for testing only
# In production, the provider will be inherited from the calling module
provider "google" {
  project = "test-project"
  region  = "us-central1"
}

# Variables
variable "test_mode" {
  description = "Set to true when running tests to skip GCP API calls"
  type        = bool
  default     = false
}

variable "disk_self_link" {
  description = "The self_link of the disk to create snapshots from"
  type        = string
}

variable "default_image" {
  description = "The default image to use when not restoring from a snapshot (e.g., debian-cloud/debian-12)"
  type        = string
}

variable "zone" {
  description = "The zone where the disk resides"
  type        = string
}

variable "project" {
  description = "The GCP project ID"
  type        = string
}

variable "labels" {
  description = "Additional labels to apply to snapshots"
  type        = map(string)
  default     = {}
}

variable "snapshot_retention_count" {
  description = "Number of snapshots to retain (default: 3)"
  type        = number
  default     = 3
}

variable "storage_locations" {
  description = "Cloud Storage bucket location to store the snapshot (regional or multi-regional)"
  type        = list(string)
  default     = []
}

# Get workspace information
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Locals for label normalization (GCP labels must be lowercase with hyphens/underscores)
locals {
  normalized_workspace_name = lower(replace(replace(data.coder_workspace.me.name, "/[^a-z0-9-_]/", "-"), "--", "-"))
  normalized_owner_name     = lower(replace(replace(data.coder_workspace_owner.me.name, "/[^a-z0-9-_]/", "-"), "--", "-"))
  normalized_template_name  = lower(replace(replace(data.coder_workspace.me.template_name, "/[^a-z0-9-_]/", "-"), "--", "-"))
}

# Use external data source to list snapshots for this workspace
# This calls gcloud to get the N most recent snapshots with matching labels
data "external" "list_snapshots" {
  count = var.test_mode ? 0 : 1

  program = ["bash", "-c", <<-EOF
    # Get snapshots matching workspace/owner labels, sorted by creation time (newest first)
    snapshots=$(gcloud compute snapshots list \
      --project="${var.project}" \
      --filter="labels.coder_workspace=${local.normalized_workspace_name} AND labels.coder_owner=${local.normalized_owner_name}" \
      --format="json(name,creationTimestamp)" \
      --sort-by="~creationTimestamp" \
      --limit=${var.snapshot_retention_count} 2>/dev/null || echo "[]")
    
    # Build JSON output with snapshot names as keys and timestamps as values
    # Also include a comma-separated list of names for easy parsing
    if [ "$snapshots" = "[]" ] || [ -z "$snapshots" ]; then
      echo '{"snapshot_list": "", "count": "0"}'
    else
      names=$(echo "$snapshots" | jq -r '[.[].name] | join(",")' 2>/dev/null || echo "")
      count=$(echo "$snapshots" | jq -r 'length' 2>/dev/null || echo "0")
      echo "{\"snapshot_list\": \"$names\", \"count\": \"$count\"}"
    fi
  EOF
  ]
}

locals {
  # Parse snapshot list from external data source
  snapshot_list_raw = var.test_mode ? "" : try(data.external.list_snapshots[0].result.snapshot_list, "")
  snapshot_count    = var.test_mode ? 0 : try(tonumber(data.external.list_snapshots[0].result.count), 0)
  
  # Convert comma-separated list to array
  available_snapshot_names = local.snapshot_list_raw != "" ? split(",", local.snapshot_list_raw) : []
  
  # Default to newest snapshot (first in list) if available
  default_snapshot = length(local.available_snapshot_names) > 0 ? local.available_snapshot_names[0] : "none"
}

# Parameter to select from available snapshots
# Defaults to the newest snapshot
data "coder_parameter" "restore_snapshot" {
  name         = "restore_snapshot"
  display_name = "Restore from Snapshot"
  description  = "Select a snapshot to restore from. Defaults to the most recent snapshot."
  type         = "string"
  default      = local.default_snapshot
  mutable      = true
  order        = 1

  option {
    name        = "Fresh disk (no snapshot)"
    value       = "none"
    description = "Start with a fresh disk using the default image"
  }

  dynamic "option" {
    for_each = local.available_snapshot_names
    content {
      name        = option.value
      value       = option.value
      description = "Snapshot ${option.key + 1} of ${length(local.available_snapshot_names)}"
    }
  }
}

# Determine which snapshot to use
locals {
  use_snapshot      = data.coder_parameter.restore_snapshot.value != "none"
  selected_snapshot = local.use_snapshot ? data.coder_parameter.restore_snapshot.value : null
  
  # Snapshot name for new snapshot (timestamp-based, unique per stop)
  new_snapshot_name = lower("${local.normalized_owner_name}-${local.normalized_workspace_name}-${formatdate("YYYYMMDDhhmmss", timestamp())}")
}

# Create snapshot when workspace is stopped
resource "google_compute_snapshot" "workspace_snapshot" {
  count       = !var.test_mode && data.coder_workspace.me.transition == "stop" ? 1 : 0
  name        = local.new_snapshot_name
  source_disk = var.disk_self_link
  zone        = var.zone
  project     = var.project

  storage_locations = length(var.storage_locations) > 0 ? var.storage_locations : null

  labels = merge(var.labels, {
    coder_workspace = local.normalized_workspace_name
    coder_owner     = local.normalized_owner_name
    coder_template  = local.normalized_template_name
    workspace_id    = data.coder_workspace.me.id
  })

  lifecycle {
    ignore_changes = [name]
  }
}

# Cleanup old snapshots beyond retention count
# This runs after creating a new snapshot
resource "terraform_data" "cleanup_old_snapshots" {
  count = !var.test_mode && data.coder_workspace.me.transition == "stop" ? 1 : 0

  triggers_replace = {
    snapshot_created = google_compute_snapshot.workspace_snapshot[0].id
  }

  provisioner "local-exec" {
    command = <<-EOF
      # List ALL snapshots for this workspace (not just the limited set from earlier)
      all_snapshots=$(gcloud compute snapshots list \
        --project="${var.project}" \
        --filter="labels.coder_workspace=${local.normalized_workspace_name} AND labels.coder_owner=${local.normalized_owner_name}" \
        --format="value(name)" \
        --sort-by="creationTimestamp")
      
      # Count total snapshots
      count=$(echo "$all_snapshots" | grep -c . || echo 0)
      
      # Calculate how many to delete (keep only N newest, which means delete oldest)
      # We add 1 because we just created a new snapshot
      retention=$((${var.snapshot_retention_count}))
      to_delete=$((count - retention))
      
      if [ $to_delete -gt 0 ]; then
        echo "Deleting $to_delete old snapshot(s) to maintain retention of $retention"
        echo "$all_snapshots" | head -n $to_delete | while read snapshot; do
          if [ -n "$snapshot" ]; then
            echo "Deleting old snapshot: $snapshot"
            gcloud compute snapshots delete "$snapshot" --project="${var.project}" --quiet 2>/dev/null || true
          fi
        done
      else
        echo "No snapshots to delete. Current count: $count, Retention: $retention"
      fi
    EOF
  }

  depends_on = [google_compute_snapshot.workspace_snapshot]
}

# Outputs
output "snapshot_self_link" {
  description = "The self_link of the selected snapshot to restore from (null if using fresh disk)"
  value       = local.use_snapshot ? "projects/${var.project}/global/snapshots/${local.selected_snapshot}" : null
}

output "use_snapshot" {
  description = "Whether a snapshot is being used"
  value       = local.use_snapshot
}

output "default_image" {
  description = "The default image to use when not using a snapshot"
  value       = var.default_image
}

output "selected_snapshot_name" {
  description = "The name of the selected snapshot (null if using fresh disk)"
  value       = local.selected_snapshot
}

output "available_snapshots" {
  description = "List of available snapshot names for this workspace"
  value       = local.available_snapshot_names
}

output "created_snapshot_name" {
  description = "The name of the snapshot created when workspace stopped (if any)"
  value       = !var.test_mode && data.coder_workspace.me.transition == "stop" ? local.new_snapshot_name : null
}
