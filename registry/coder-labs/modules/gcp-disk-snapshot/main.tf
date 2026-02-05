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
  }
}

# Provider configuration for testing only
# In production, the provider will be inherited from the calling module
# Note: Using fake credentials for CI testing - Terraform will still validate syntax
provider "google" {
  project = "test-project"
  region  = "us-central1"

  # Fake credentials for testing - allows terraform plan/apply to run
  # without actual GCP authentication in CI environments
  credentials = jsonencode({
    type                        = "service_account"
    project_id                  = "test-project"
    private_key_id              = "key-id"
    private_key                 = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGy0ARL00FVaKUOclBo0vo9C\nWL23EQJ2dWLV5g8k8DjFYIrXvARQPIDs0d+6UgKNKFjHmcZrj9i+e9v8zhVLB2wc\nfU2xsf3AJzLWr7L/LN6GEfT6m7kqKvBB6mJhpFn9RSAZ6WNvnOv1IVVQEq5Tfjlw\nGiJI0q0T8JmEobVSAaRJa7ZKQH1tBjTxcbr+EajVh5F2n7E0VqJNVNT5c5s8MJW0\nrn6AKaEVwmr3SW/NKQX6LxHRgVLJoWcL9j9B9cQ5Mz7u6h/oTrKLLt1v5NKvO9d8\ng39z7cKd1O6kd8nE3hZD7w5d0ileH9u9wZNPFwIDAQABAoIBADvhw8GIB0/G7mFP\ntest-fake-key-data-for-ci-testing-only\n-----END RSA PRIVATE KEY-----\n"
    client_email                = "test@test-project.iam.gserviceaccount.com"
    client_id                   = "123456789"
    auth_uri                    = "https://accounts.google.com/o/oauth2/auth"
    token_uri                   = "https://oauth2.googleapis.com/token"
    auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
    client_x509_cert_url        = "https://www.googleapis.com/robot/v1/metadata/x509/test%40test-project.iam.gserviceaccount.com"
  })
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
  description = "Number of snapshots to retain (1-3, default: 3). Uses rotating snapshot slots."
  type        = number
  default     = 3

  validation {
    condition     = var.snapshot_retention_count >= 1 && var.snapshot_retention_count <= 3
    error_message = "snapshot_retention_count must be between 1 and 3."
  }
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

  # Base name for snapshots - uses rotating slots (1, 2, 3)
  snapshot_base_name = "${local.normalized_owner_name}-${local.normalized_workspace_name}"

  # Snapshot slot names (fixed, predictable names for rotation)
  snapshot_slot_names = [
    for i in range(var.snapshot_retention_count) : "${local.snapshot_base_name}-slot-${i + 1}"
  ]
}

# Try to read existing snapshots to determine which slots are used
# This data source will fail gracefully if snapshot doesn't exist
data "google_compute_snapshot" "existing_snapshots" {
  for_each = var.test_mode ? toset([]) : toset(local.snapshot_slot_names)
  name     = each.value
  project  = var.project
}

locals {
  # Determine which snapshots actually exist (have data)
  existing_snapshot_names = var.test_mode ? [] : [
    for name, snapshot in data.google_compute_snapshot.existing_snapshots : name
    if can(snapshot.self_link)
  ]

  # Sort by creation timestamp to find newest (for default selection)
  # Since we can't easily sort in Terraform without timestamps, we'll use slot order
  # Slot with highest number that exists is likely newest
  available_snapshots = reverse(sort(local.existing_snapshot_names))

  # Default to newest available snapshot
  default_snapshot = length(local.available_snapshots) > 0 ? local.available_snapshots[0] : "none"

  # Calculate next slot to use (round-robin)
  # Count existing snapshots and use next slot, or slot 1 if all are full
  next_slot_index = length(local.existing_snapshot_names) >= var.snapshot_retention_count ? 0 : length(local.existing_snapshot_names)
  next_snapshot_name = local.snapshot_slot_names[local.next_slot_index]
}

# Parameter to select from available snapshots
# Defaults to the most recent snapshot
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
    for_each = local.available_snapshots
    content {
      name        = option.value
      value       = option.value
      description = "Restore from snapshot: ${option.value}"
    }
  }
}

# Determine which snapshot to use
locals {
  use_snapshot      = data.coder_parameter.restore_snapshot.value != "none"
  selected_snapshot = local.use_snapshot ? data.coder_parameter.restore_snapshot.value : null
}

# Create snapshot when workspace is stopped
# Uses the next available slot in rotation
resource "google_compute_snapshot" "workspace_snapshot" {
  count       = !var.test_mode && data.coder_workspace.me.transition == "stop" ? 1 : 0
  name        = local.next_snapshot_name
  source_disk = var.disk_self_link
  zone        = var.zone
  project     = var.project

  storage_locations = length(var.storage_locations) > 0 ? var.storage_locations : null

  labels = merge(var.labels, {
    coder_workspace = local.normalized_workspace_name
    coder_owner     = local.normalized_owner_name
    coder_template  = local.normalized_template_name
    workspace_id    = data.coder_workspace.me.id
    slot_number     = tostring(local.next_slot_index + 1)
  })

  lifecycle {
    # Allow replacing snapshots in the same slot
    create_before_destroy = false
  }
}

# Outputs
output "snapshot_self_link" {
  description = "The self_link of the selected snapshot to restore from (null if using fresh disk)"
  value       = local.use_snapshot && !var.test_mode ? "projects/${var.project}/global/snapshots/${local.selected_snapshot}" : null
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
  value       = local.available_snapshots
}

output "created_snapshot_name" {
  description = "The name of the snapshot created when workspace stopped (if any)"
  value       = !var.test_mode && data.coder_workspace.me.transition == "stop" ? local.next_snapshot_name : null
}

output "snapshot_slots" {
  description = "The snapshot slot names used for rotation"
  value       = local.snapshot_slot_names
}
