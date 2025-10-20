---
display_name: Restic Backup
description: Cloud-backed ephemeral workspaces with automatic backup on stop and restore on start using Restic
icon: ../../../../.icons/restic.svg
verified: false
tags: [backup, restore, cloud, restic, s3, b2]
---

# Restic Backup

Automatic cloud backups for Coder workspaces. Backs up on stop, restores on start.

## Features

- Auto backup/restore on workspace stop/start
- Works with S3, B2, Azure, GCS, SFTP, local storage
- Encrypted and deduplicated
- Workspace-aware tagging for easy browsing
- Configurable retention policies
- Clone backups between workspaces

## Quick Start

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/my-workspace-backups"
  password   = var.restic_password

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
  }
}
```

## How It Works

1. Workspace stops → automatic backup to cloud
2. Workspace starts → automatic restore from backup
3. Backups are tagged with `workspace-id`, `workspace-owner`, `workspace-name`
4. Auto-restore uses `workspace-id` to find the correct backup
5. Manually restore any backup using `snapshot_id`

## Storage Backend Configuration

### AWS S3

[Official Restic S3 Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#amazon-s3)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/my-bucket/workspace-backups"
  password   = var.restic_password

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
    AWS_DEFAULT_REGION    = "us-east-1"
  }
}
```

### Backblaze B2 (Cost-Effective)

[Official Restic B2 Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#backblaze-b2)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "b2:my-bucket:workspace-backups"
  password   = var.restic_password

  env = {
    B2_ACCOUNT_ID  = var.b2_account_id
    B2_ACCOUNT_KEY = var.b2_account_key
  }
}
```

### Azure Blob Storage

[Official Restic Azure Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#microsoft-azure-blob-storage)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "azure:container-name:/workspace-backups"
  password   = var.restic_password

  env = {
    AZURE_ACCOUNT_NAME = var.azure_account_name
    AZURE_ACCOUNT_KEY  = var.azure_account_key
  }
}
```

### Google Cloud Storage

[Official Restic GCS Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#google-cloud-storage)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "gs:my-bucket:/workspace-backups"
  password   = var.restic_password

  env = {
    GOOGLE_PROJECT_ID              = var.gcp_project_id
    GOOGLE_APPLICATION_CREDENTIALS = "/path/to/service-account.json"
  }
}
```

### MinIO or S3-Compatible Storage

[Official Restic Minio Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#minio-server) | [S3-Compatible](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#s3-compatible-storage)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:http://minio.company.com:9000/workspace-backups"
  password   = var.restic_password

  env = {
    AWS_ACCESS_KEY_ID     = var.minio_access_key
    AWS_SECRET_ACCESS_KEY = var.minio_secret_key
  }
}
```

### SFTP

[Official Restic SFTP Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#sftp)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "sftp:user@backup-server.com:/backups/restic"
  password   = var.restic_password

  # SSH key should be at ~/.ssh/id_rsa
  # Or configure custom SSH command:
  env = {
    RESTIC_SFTP_COMMAND = "ssh user@host -i /path/to/key -s sftp"
  }
}
```

### Local Directory (Testing)

[Official Restic Local Documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#local)

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "/backup/restic-repo"
  password   = var.restic_password
}
```

**Note:** Use persistent storage (Docker volume, PV) for local repositories.

## Advanced Configuration

### Selective Backup Paths

Only backup specific directories:

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/backups"
  password   = var.restic_password

  backup_paths = [
    "/home/coder/projects",
    "/home/coder/.config",
    "/home/coder/data",
  ]

  exclude_patterns = [
    "**/.git",
    "**/node_modules",
    "**/__pycache__",
    "**/target",
    "**/.venv",
    "**/tmp",
  ]

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
  }
}
```

### Periodic Backups While Running

Backup every N minutes while workspace is active:

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "b2:workspace-backups"
  password   = var.restic_password

  # Backup every 30 minutes while workspace is running
  backup_interval_minutes = 30

  env = {
    B2_ACCOUNT_ID  = var.b2_account_id
    B2_ACCOUNT_KEY = var.b2_account_key
  }
}
```

### Custom Stop Script

Run cleanup before backup:

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/backups"
  password   = var.restic_password

  custom_stop_script = <<-EOF
    #!/bin/bash
    echo "Cleaning up before backup..."
    rm -rf /tmp/*
    docker system prune -f
    find /home/coder -name "*.log" -delete
  EOF

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
  }
}
```

### Clone Another Workspace's Backup

Restore from a specific snapshot:

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/backups"
  password   = var.restic_password

  # Restore from specific snapshot (find ID using: restic snapshots)
  restore_on_start = true
  snapshot_id      = "abc123def" # The snapshot ID to restore

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
  }
}
```

To find snapshot IDs from another workspace:

```bash
# List all snapshots grouped by workspace
restic snapshots --group-by tags

# Or filter by specific workspace
restic snapshots --tag workspace-owner:john --tag workspace-name:dev-workspace
```

### Custom Retention Policies

Control how many backups to keep:

```tf
module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/backups"
  password   = var.restic_password

  # Keep last 10 backups
  retention_keep_last = 10

  # Keep daily backups for 14 days
  retention_keep_daily = 14

  # Keep weekly backups for 8 weeks
  retention_keep_weekly = 8

  # Keep monthly backups for 6 months
  retention_keep_monthly = 6

  # Apply retention automatically
  auto_forget = true

  # Don't prune on stop (too slow)
  auto_prune = false

  env = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
  }
}
```

### Using HCP Vault Secrets

Store credentials securely:

```tf
module "vault_secrets" {
  source     = "registry.coder.com/coder/hcp-vault-secrets/coder"
  version    = "1.0.34"
  agent_id   = coder_agent.main.id
  app_name   = "workspace-backups"
  project_id = var.hcp_project_id
  secrets    = ["RESTIC_PASSWORD", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"]
}

module "restic" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/restic/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.main.id
  repository = "s3:s3.amazonaws.com/backups"
  password   = "" # Will use RESTIC_PASSWORD from vault

  depends_on = [module.vault_secrets]
}
```

## Manual Operations

### Trigger Manual Backup

Click the **"Backup Now"** button in the Coder UI, or run from terminal:

```bash
restic-backup --tag manual-backup
```

### List Your Workspace's Backups

```bash
restic snapshots --tag workspace-id:$RESTIC_WORKSPACE_ID
```

Or view all snapshots:

```bash
restic snapshots
```

### List All Workspace Backups in Repository

```bash
restic snapshots --group-by tags
```

This shows snapshots grouped by workspace, making it easy to see all workspace backups in the repository.

### Restore Specific Snapshot

```bash
# List snapshots for this workspace
restic snapshots --tag workspace-id:$RESTIC_WORKSPACE_ID

# Restore to temporary location for inspection
restic restore /tmp/restore < snapshot-id > --target

# Or restore to original location
restic restore / < snapshot-id > --target
```

### Check Repository Health

```bash
restic check
```

### Manual Cleanup

```bash
# Remove old snapshots for this workspace
restic forget --tag workspace-id:$RESTIC_WORKSPACE_ID --keep-last 3

# Reclaim space (removes unreferenced data)
restic prune
```

## Important Considerations

### Stop Backup Limitations

> **Warning**: The `backup_on_stop` feature may not work on all template types if the agent is terminated before backup completes. See [coder/coder#6174](https://github.com/coder/coder/issues/6174) for details.

**Recommendations**:

- Test stop backups with your specific template
- Keep backups fast (use selective paths and exclusions)
- Use `backup_interval_minutes` for important data
- Set `auto_prune = false` for stop backups (prune is slow)

### Repository Organization

**Single Shared Repository** (Recommended):

- All workspaces share one repository
- Backups are tagged with workspace metadata
- Deduplication saves space
- Easy credential management

**Per-Workspace Repositories**:

- Each workspace uses separate repository
- More isolation but more complex
- No cross-workspace restore

### Security

- Repository password encrypts ALL backups
- Use Coder parameters or external secrets for credentials
- Backend credentials should have minimal permissions
- Consider separate repositories for different teams

### Performance Tips

- **Use exclusions**: Skip `.git`, `node_modules`, caches
- **Selective paths**: Only backup what you need
- **Interval backups**: Balance frequency vs performance
- **Retention policies**: Keep low retention to save storage costs
- **Prune manually**: Don't enable `auto_prune` on stop (too slow)

## Troubleshooting

### Backup Fails on Stop

The workspace might be terminating before backup completes. Try:

- Reducing backup size with selective paths
- Using interval backups instead
- Testing with a local repository first

### Restore Blocks Login Too Long

- Reduce restore size with selective backup paths
- Set `start_blocks_login = false` to allow login during restore
- Use faster storage backend

### Repository Not Found

Ensure:

- Repository URL is correct
- Backend credentials are valid
- Network connectivity to storage backend
- Repository has been initialized (`auto_init_repo = true`)

### Permission Denied

Check:

- Backend credentials have write permissions
- Local directory (if used) is writable
- SSH key (for SFTP) is accessible

### Out of Storage Space

Run cleanup:

```bash
restic forget --tag workspace-id:$RESTIC_WORKSPACE_ID --keep-last 2
restic prune
```

## Links

- [Restic Documentation](https://restic.readthedocs.io/)
- [Restic GitHub](https://github.com/restic/restic)
- [Coder Documentation](https://coder.com/docs)
