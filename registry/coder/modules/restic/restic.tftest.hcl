run "required_variables" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "s3:s3.amazonaws.com/test-bucket"
    password   = "test-password"
  }
}

run "stop_backup_script_created_when_enabled" {
  command = plan

  variables {
    agent_id       = "test-agent"
    repository     = "/tmp/restic-repo"
    password       = "test-password"
    backup_on_stop = true
  }

  assert {
    condition     = coder_script.stop_backup[0].run_on_stop == true
    error_message = "Stop backup script should have run_on_stop enabled"
  }

  assert {
    condition     = coder_script.stop_backup[0].agent_id == "test-agent"
    error_message = "Stop backup script should use correct agent_id"
  }
}

run "stop_backup_script_not_created_when_disabled" {
  command = plan

  variables {
    agent_id       = "test-agent"
    repository     = "/tmp/restic-repo"
    password       = "test-password"
    backup_on_stop = false
  }

  assert {
    condition     = length(coder_script.stop_backup) == 0
    error_message = "Stop backup script should not be created when backup_on_stop is false"
  }
}

run "restore_blocks_login_by_default" {
  command = plan

  variables {
    agent_id         = "test-agent"
    repository       = "/tmp/restic-repo"
    password         = "test-password"
    restore_on_start = true
  }

  assert {
    condition     = coder_script.install_and_restore.start_blocks_login == true
    error_message = "Install script should block login when restore_on_start and start_blocks_login are true"
  }
}

run "restore_does_not_block_login_when_disabled" {
  command = plan

  variables {
    agent_id           = "test-agent"
    repository         = "/tmp/restic-repo"
    password           = "test-password"
    restore_on_start   = true
    start_blocks_login = false
  }

  assert {
    condition     = coder_script.install_and_restore.start_blocks_login == false
    error_message = "Install script should not block login when start_blocks_login is false"
  }
}

run "workspace_metadata_env_vars_created" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "/tmp/restic-repo"
    password   = "test-password"
  }

  assert {
    condition     = coder_env.workspace_owner.name == "RESTIC_WORKSPACE_OWNER"
    error_message = "Workspace owner env var should be RESTIC_WORKSPACE_OWNER"
  }

  assert {
    condition     = coder_env.workspace_name.name == "RESTIC_WORKSPACE_NAME"
    error_message = "Workspace name env var should be RESTIC_WORKSPACE_NAME"
  }

  assert {
    condition     = coder_env.workspace_id.name == "RESTIC_WORKSPACE_ID"
    error_message = "Workspace ID env var should be RESTIC_WORKSPACE_ID"
  }
}

run "core_env_vars_created" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "s3:s3.amazonaws.com/bucket"
    password   = "secure-password"
  }

  assert {
    condition     = coder_env.restic_repository.name == "RESTIC_REPOSITORY"
    error_message = "Repository env var should be RESTIC_REPOSITORY"
  }

  assert {
    condition     = coder_env.restic_repository.value == "s3:s3.amazonaws.com/bucket"
    error_message = "Repository env var should match input"
  }

  assert {
    condition     = coder_env.restic_password.name == "RESTIC_PASSWORD"
    error_message = "Password env var should be RESTIC_PASSWORD"
  }
}

run "safe_retention_defaults" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "/tmp/restic-repo"
    password   = "test-password"
  }

  # Verify auto_forget is false by default (safe)
  assert {
    condition     = var.auto_forget == false
    error_message = "auto_forget should be false by default for safety"
  }

  # Verify reasonable retention defaults
  assert {
    condition     = var.retention_keep_last == 10
    error_message = "Default retention_keep_last should be 10"
  }

  assert {
    condition     = var.retention_keep_daily == 14
    error_message = "Default retention_keep_daily should be 14"
  }
}

run "manual_backup_app_created" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "/tmp/restic-repo"
    password   = "test-password"
  }

  assert {
    condition     = coder_app.restic_backup.slug == "restic-backup"
    error_message = "Backup app should have slug restic-backup"
  }

  assert {
    condition     = coder_app.restic_backup.display_name == "Backup Now"
    error_message = "Backup app should display 'Backup Now'"
  }

  assert {
    condition     = can(regex("restic-backup", coder_app.restic_backup.command))
    error_message = "Backup app command should call restic-backup helper"
  }
}

run "install_restic_enabled_in_script" {
  command = plan

  variables {
    agent_id       = "test-agent"
    repository     = "/tmp/restic-repo"
    password       = "test-password"
    install_restic = true
  }

  assert {
    condition     = can(regex("INSTALL_RESTIC=\"true\"", coder_script.install_and_restore.script))
    error_message = "Script should have INSTALL_RESTIC set to true"
  }
}

run "install_restic_disabled_in_script" {
  command = plan

  variables {
    agent_id       = "test-agent"
    repository     = "/tmp/restic-repo"
    password       = "test-password"
    install_restic = false
  }

  assert {
    condition     = can(regex("INSTALL_RESTIC=\"false\"", coder_script.install_and_restore.script))
    error_message = "Script should have INSTALL_RESTIC set to false"
  }
}

run "auto_init_repo_configuration" {
  command = plan

  variables {
    agent_id       = "test-agent"
    repository     = "/tmp/restic-repo"
    password       = "test-password"
    auto_init_repo = false
  }

  assert {
    condition     = can(regex("AUTO_INIT=\"false\"", coder_script.install_and_restore.script))
    error_message = "Script should have AUTO_INIT set to false"
  }
}

run "restore_on_start_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent"
    repository       = "/tmp/restic-repo"
    password         = "test-password"
    restore_on_start = true
    snapshot_id      = "abc123"
  }

  assert {
    condition     = can(regex("RESTORE_ON_START=\"true\"", coder_script.install_and_restore.script))
    error_message = "Script should have RESTORE_ON_START set to true"
  }

  assert {
    condition     = can(regex("SNAPSHOT_ID=\"abc123\"", coder_script.install_and_restore.script))
    error_message = "Script should have SNAPSHOT_ID set to abc123"
  }
}

run "interval_backup_configuration" {
  command = plan

  variables {
    agent_id                = "test-agent"
    repository              = "/tmp/restic-repo"
    password                = "test-password"
    backup_interval_minutes = 30
  }

  assert {
    condition     = can(regex("BACKUP_INTERVAL=\"30\"", coder_script.install_and_restore.script))
    error_message = "Script should have BACKUP_INTERVAL set to 30"
  }
}

run "interval_backup_disabled_by_default" {
  command = plan

  variables {
    agent_id   = "test-agent"
    repository = "/tmp/restic-repo"
    password   = "test-password"
  }

  assert {
    condition     = can(regex("BACKUP_INTERVAL=\"0\"", coder_script.install_and_restore.script))
    error_message = "Script should have BACKUP_INTERVAL set to 0 by default"
  }
}

run "backup_paths_and_exclusions_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent"
    repository       = "/tmp/restic-repo"
    password         = "test-password"
    backup_paths     = ["/home/coder", "/workspace"]
    exclude_patterns = ["*.log", "node_modules"]
    backup_tags      = ["production", "daily"]
  }

  assert {
    condition     = can(regex("/home/coder", coder_script.install_and_restore.script))
    error_message = "Script should contain backup path /home/coder"
  }

  assert {
    condition     = can(regex("/workspace", coder_script.install_and_restore.script))
    error_message = "Script should contain backup path /workspace"
  }

  assert {
    condition     = can(regex("\\*.log", coder_script.install_and_restore.script))
    error_message = "Script should contain exclude pattern *.log"
  }

  assert {
    condition     = can(regex("production", coder_script.install_and_restore.script))
    error_message = "Script should contain backup tag production"
  }
}

run "custom_stop_script_included" {
  command = plan

  variables {
    agent_id           = "test-agent"
    repository         = "/tmp/restic-repo"
    password           = "test-password"
    backup_on_stop     = true
    custom_stop_script = "echo 'Pre-backup cleanup'"
  }

  assert {
    condition     = can(regex("echo 'Pre-backup cleanup'", coder_script.stop_backup[0].script))
    error_message = "Stop script should contain custom stop script"
  }
}

