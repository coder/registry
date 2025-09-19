terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "paths" {
  description = "List of files/directories to include in the archive. Defaults to the current directory."
  type        = list(string)
  default     = ["."]
}

variable "exclude_patterns" {
  description = "Exclude patterns for the archive."
  type        = list(string)
  default     = []
}

variable "compression" {
  description = "Compression algorithm for the archive. Supported: gzip, zstd, none."
  type        = string
  default     = "gzip"
  validation {
    condition     = contains(["gzip", "zstd", "none"], var.compression)
    error_message = "compression must be one of: gzip, zstd, none."
  }
}

variable "archive_name" {
  description = "Optional archive base name without extension. If empty, defaults to \"coder-archive\"."
  type        = string
  default     = "coder-archive"
}

variable "output_dir" {
  description = "Optional output directory where the archive will be written. Defaults to \"/tmp\"."
  type        = string
  default     = "/tmp"
}

variable "directory" {
  description = "Change current directory to this path before creating or extracting the archive. Defaults to the user's home directory."
  type        = string
  default     = "~"
}

variable "create_on_stop" {
  description = "If true, also create a run_on_stop script that creates the archive automatically on workspace stop."
  type        = bool
  default     = false
}

variable "extract_on_start" {
  description = "If true, the installer will wait for an archive and extract it on start."
  type        = bool
  default     = false
}

variable "extract_wait_timeout_seconds" {
  description = "Timeout (seconds) to wait for an archive when extract_on_start is true."
  type        = number
  default     = 300
}

# Provide a stable script filename and sensible defaults.
locals {
  extension = var.compression == "gzip" ? ".tar.gz" : var.compression == "zstd" ? ".tar.zst" : ".tar"

  # Ensure ~ is expanded because it cannot be expanded inside quotes in a
  # templated shell script.
  paths            = [for v in var.paths : replace(v, "/^~/", "$$HOME")]
  exclude_patterns = [for v in var.exclude_patterns : replace(v, "/^~/", "$$HOME")]
  directory        = replace(var.directory, "/^~/", "$$HOME")
  output_dir       = replace(var.output_dir, "/^~/", "$$HOME")

  archive_path = "${local.output_dir}/${var.archive_name}${local.extension}"
}

output "archive_path" {
  description = "Full path to the archive file that will be created, extracted, or both."
  value       = local.archive_path
}

# This script installs the user-facing archive script into $CODER_SCRIPT_BIN_DIR.
# The installed script can be run manually by the user to create an archive.
resource "coder_script" "archive_start_script" {
  agent_id           = var.agent_id
  display_name       = "Archive"
  icon               = "/icon/folder-zip.svg"
  run_on_start       = true
  start_blocks_login = var.extract_on_start

  # Render the user-facing archive script with Terraform defaults, then write it to $CODER_SCRIPT_BIN_DIR
  script = templatefile("${path.module}/run.sh", {
    TF_LIB_B64              = base64encode(file("${path.module}/scripts/archive-lib.sh")),
    TF_PATHS                = join(" ", formatlist("%q", local.paths)),
    TF_EXCLUDE_PATTERNS     = join(" ", formatlist("%q", local.exclude_patterns)),
    TF_COMPRESSION          = var.compression,
    TF_ARCHIVE_PATH         = local.archive_path,
    TF_DIRECTORY            = local.directory,
    TF_EXTRACT_ON_START     = var.extract_on_start,
    TF_EXTRACT_WAIT_TIMEOUT = var.extract_wait_timeout_seconds,
  })
}

# Optionally, also register a run_on_stop script that creates the archive automatically
# when the workspace stops. It simply invokes the installed archive script.
resource "coder_script" "archive_stop_script" {
  count              = var.create_on_stop ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Archive"
  icon               = "/icon/folder-zip.svg"
  run_on_stop        = true
  start_blocks_login = false

  # Call the installed script. It will log to stderr and print the archive path to stdout.
  # We redirect stdout to stderr to avoid surfacing the path in system logs if undesired.
  # Remove the redirection if you want the path to appear in stdout on stop as well.
  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    "$CODER_SCRIPT_BIN_DIR/coder-create-archive"
  EOT
}
