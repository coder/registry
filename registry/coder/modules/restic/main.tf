terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "repository" {
  type        = string
  description = "Restic repository location (e.g., 's3:s3.amazonaws.com/bucket', 'b2:bucket-name', '/local/path')."
}

variable "password" {
  type        = string
  description = "Password for encrypting the Restic repository. Keep this secure!"
  sensitive   = true
}

variable "install_restic" {
  type        = bool
  description = "Whether to install Restic binary."
  default     = true
}

variable "restic_version" {
  type        = string
  description = "Version of Restic to install (e.g., '0.16.4' or 'latest')."
  default     = "latest"
}

variable "backup_paths" {
  type        = list(string)
  description = "List of paths to backup. Can be absolute or relative to 'directory'."
  default     = ["/home/coder"]
}

variable "exclude_patterns" {
  type        = list(string)
  description = "Patterns to exclude from backup (e.g., ['**/.git', '**/node_modules'])."
  default     = []
}

variable "backup_tags" {
  type        = list(string)
  description = "Additional tags to apply to all snapshots."
  default     = []
}

variable "directory" {
  type        = string
  description = "Working directory for backup operations."
  default     = "~"
}

variable "backup_on_stop" {
  type        = bool
  description = "Whether to automatically backup when workspace stops."
  default     = true
}

variable "backup_interval_minutes" {
  type        = number
  description = "Backup every N minutes while workspace is running (0 = disabled)."
  default     = 0
}

variable "restore_on_start" {
  type        = bool
  description = "Whether to restore from backup when workspace starts."
  default     = true
}

variable "snapshot_id" {
  type        = string
  description = "Specific snapshot ID to restore. If empty and restore_on_start is true, restores latest backup of this workspace. If set, restores that specific snapshot (useful for cloning workspaces)."
  default     = ""
}

variable "restore_target" {
  type        = string
  description = "Target directory for restore ('/' restores to original paths)."
  default     = "/"
}

variable "start_blocks_login" {
  type        = bool
  description = "Whether to block login until restore completes."
  default     = true
}

variable "custom_stop_script" {
  type        = string
  description = "Custom script to run before stop backup."
  default     = ""
}

variable "retention_keep_last" {
  type        = number
  description = "Keep last N snapshots per workspace."
  default     = 10
}

variable "retention_keep_daily" {
  type        = number
  description = "Keep daily snapshots for N days."
  default     = 14
}

variable "retention_keep_weekly" {
  type        = number
  description = "Keep weekly snapshots for N weeks."
  default     = 8
}

variable "retention_keep_monthly" {
  type        = number
  description = "Keep monthly snapshots for N months."
  default     = 6
}

variable "auto_forget" {
  type        = bool
  description = "Apply retention policies automatically after backup."
  default     = false
}

variable "auto_prune" {
  type        = bool
  description = "Run prune after forget to reclaim space (slower but frees storage)."
  default     = false
}

variable "auto_init_repo" {
  type        = bool
  description = "Automatically initialize repository if it doesn't exist."
  default     = true
}

variable "env" {
  type        = map(string)
  description = "Environment variables for backend configuration (e.g., AWS_ACCESS_KEY_ID, B2_ACCOUNT_KEY). See README for backend-specific examples."
  default     = {}
  sensitive   = true
}

variable "icon" {
  type        = string
  description = "Icon to use for Restic apps."
  default     = "/icon/restic.svg"
}

variable "order" {
  type        = number
  description = "Order of apps in UI."
  default     = null
}

variable "group" {
  type        = string
  description = "Group name for apps."
  default     = null
}

resource "coder_env" "restic_repository" {
  agent_id = var.agent_id
  name     = "RESTIC_REPOSITORY"
  value    = var.repository
}

resource "coder_env" "restic_password" {
  agent_id = var.agent_id
  name     = "RESTIC_PASSWORD"
  value    = var.password
}

resource "coder_env" "backend_env" {
  for_each = nonsensitive(var.env)
  agent_id = var.agent_id
  name     = each.key
  value    = each.value
}

resource "coder_env" "workspace_owner" {
  agent_id = var.agent_id
  name     = "RESTIC_WORKSPACE_OWNER"
  value    = data.coder_workspace_owner.me.name
}

resource "coder_env" "workspace_name" {
  agent_id = var.agent_id
  name     = "RESTIC_WORKSPACE_NAME"
  value    = data.coder_workspace.me.name
}

resource "coder_env" "workspace_id" {
  agent_id = var.agent_id
  name     = "RESTIC_WORKSPACE_ID"
  value    = data.coder_workspace.me.id
}

resource "coder_script" "install_and_restore" {
  agent_id           = var.agent_id
  display_name       = "Restic Setup"
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = var.restore_on_start && var.start_blocks_login

  script = templatefile("${path.module}/scripts/run.sh", {
    INSTALL_RESTIC    = var.install_restic
    RESTIC_VERSION    = var.restic_version
    AUTO_INIT         = var.auto_init_repo
    RESTORE_ON_START  = var.restore_on_start
    SNAPSHOT_ID       = var.snapshot_id
    RESTORE_TARGET    = var.restore_target
    BACKUP_INTERVAL   = var.backup_interval_minutes
    BACKUP_PATHS      = jsonencode(var.backup_paths)
    EXCLUDE_PATTERNS  = jsonencode(var.exclude_patterns)
    BACKUP_TAGS       = jsonencode(var.backup_tags)
    DIRECTORY         = var.directory
    RETENTION_LAST    = var.retention_keep_last
    RETENTION_DAILY   = var.retention_keep_daily
    RETENTION_WEEKLY  = var.retention_keep_weekly
    RETENTION_MONTHLY = var.retention_keep_monthly
    AUTO_FORGET       = var.auto_forget
    AUTO_PRUNE        = var.auto_prune
    BACKUP_SCRIPT_B64 = base64encode(file("${path.module}/scripts/backup.sh"))
  })
}

resource "coder_script" "stop_backup" {
  count              = var.backup_on_stop ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Restic Backup"
  icon               = var.icon
  run_on_stop        = true
  start_blocks_login = false

  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    
    ${var.custom_stop_script}
    
    "$CODER_SCRIPT_BIN_DIR/restic-backup" --tag "stop-backup"
  EOT
}

resource "coder_app" "restic_backup" {
  agent_id     = var.agent_id
  slug         = "restic-backup"
  display_name = "Backup Now"
  icon         = var.icon
  order        = var.order
  group        = var.group

  command = "$CODER_SCRIPT_BIN_DIR/restic-backup --tag manual-backup"
}

