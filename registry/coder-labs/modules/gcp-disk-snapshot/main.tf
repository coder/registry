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

  # Single snapshot name per workspace
  snapshot_name = "${local.normalized_owner_name}-${local.normalized_workspace_name}-snapshot"
}

# Try to read existing snapshot for this workspace
data "google_compute_snapshot" "workspace_snapshot" {
  count   = var.test_mode ? 0 : 1
  name    = local.snapshot_name
  project = var.project
}

locals {
  # Check if snapshot exists
  snapshot_exists = var.test_mode ? false : can(data.google_compute_snapshot.workspace_snapshot[0].self_link)

  # Default to using snapshot if it exists
  default_restore = local.snapshot_exists ? "snapshot" : "none"
}

# Parameter to choose whether to restore from snapshot
data "coder_parameter" "restore_snapshot" {
  name         = "restore_snapshot"
  display_name = "Restore from Snapshot"
  description  = "Restore workspace from the last snapshot, or start fresh."
  type         = "string"
  default      = local.default_restore
  mutable      = true
  order        = 1

  option {
    name        = "Fresh disk (no snapshot)"
    value       = "none"
    description = "Start with a fresh disk using the default image"
  }

  dynamic "option" {
    for_each = local.snapshot_exists ? [1] : []
    content {
      name        = "Restore from snapshot"
      value       = "snapshot"
      description = "Restore from: ${local.snapshot_name}"
    }
  }
}

locals {
  use_snapshot = data.coder_parameter.restore_snapshot.value == "snapshot" && local.snapshot_exists
}

# Create/update snapshot when workspace is stopped
resource "google_compute_snapshot" "workspace_snapshot" {
  count       = !var.test_mode && data.coder_workspace.me.transition == "stop" ? 1 : 0
  name        = local.snapshot_name
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
}

# Outputs
output "snapshot_self_link" {
  description = "The self_link of the snapshot to restore from (null if not using snapshot)"
  value       = local.use_snapshot ? data.google_compute_snapshot.workspace_snapshot[0].self_link : null
}

output "use_snapshot" {
  description = "Whether a snapshot is being used"
  value       = local.use_snapshot
}

output "default_image" {
  description = "The default image to use when not using a snapshot"
  value       = var.default_image
}

output "snapshot_name" {
  description = "The name of the workspace snapshot"
  value       = local.snapshot_name
}

output "snapshot_exists" {
  description = "Whether a snapshot exists for this workspace"
  value       = local.snapshot_exists
}
