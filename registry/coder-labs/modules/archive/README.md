---
display_name: Archive
description: Create automated and user-invocable scripts that archive and extract selected files/directories with optional compression (gzip or zstd).
icon: ../../../../.icons/tool.svg
verified: false
tags: [backup, archive, tar, helper]
---

# Archive

This module installs small, robust scripts in your workspace to create and extract tar archives from a list of files and directories. It supports optional compression (gzip or zstd). The create command prints only the resulting archive path to stdout; operational logs go to stderr. An optional stop hook can also create an archive automatically when the workspace stops, and an optional start hook can wait for an archive on-disk and extract it on start.

```tf
module "archive" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/archive/coder"
  version  = "0.0.1"
  agent_id = coder_agent.example.id

  paths = ["./projects", "./code"]
}
```

## Features

- Installs two commands into the workspace `$PATH`: `coder-archive-create` and `coder-archive-extract`.
- Creates a single `.tar`, `.tar.gz`, or `.tar.zst` containing selected paths (depends on `tar`).
- Optional compression: `gzip`, `zstd` (depends on `gzip` or `zstd`).
- Stores defaults so commands can be run without arguments (supports overriding via CLI flags).
- Logs and status messages go to stderr, the create command prints only the final archive path to stdout.
- Optional:
  - `create_on_stop` to create an archive automatically when the workspace stops.
  - `extract_on_start` to wait for an archive to appear and extract it on start.

## Usage

Basic example:

```tf
module "archive" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/archive/coder"
  version  = "0.0.1"
  agent_id = coder_agent.example.id

  # Paths to include in the archive (files or directories).
  directory = "~"
  paths = [
    "./projects",
    "./code",
  ]
}
```

Customize compression and output:

```tf
module "archive" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/archive/coder"
  version  = "0.0.1"
  agent_id = coder_agent.example.id

  directory    = "/"
  paths        = ["/etc", "/home"]
  compression  = "zstd"        # "gzip" | "zstd" | "none"
  output_dir   = "/tmp/backup" # defaults to /tmp
  archive_name = "my-backup"   # base name (extension is inferred from compression)
}
```

Enable auto-archive on stop:

```tf
module "archive" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/archive/coder"
  version  = "0.0.1"
  agent_id = coder_agent.example.id

  # Creates /tmp/coder-archive.tar.gz of the users home directory (defaults).
  create_on_stop = true
}
```

Extract on start:

```tf
module "archive" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/archive/coder"
  version  = "0.0.1"
  agent_id = coder_agent.example.id

  # Where to look for the archive file to extract:
  output_dir   = "/tmp"
  archive_name = "my-archive"
  compression  = "gzip"

  # Waits up to 5 minutes for /tmp/my-archive.tar.gz to be present.
  extract_on_start             = true
  extract_wait_timeout_seconds = 300
}
```

## Inputs

- `agent_id` (string, required): The ID of a Coder agent.
- `paths` (list(string), default: `["."]`): Files/directories to include when creating an archive.
- `exclude_patterns` (list(string), default: `[]`): Patterns to exclude (passed to tar via `--exclude`).
- `compression` (string, default: `"gzip"`): One of `gzip`, `zstd`, or `none`.
- `archive_name` (string, default: `"coder-archive"`): Base archive name (extension is inferred from `compression`).
- `output_dir` (string, default: `"/tmp"`): Directory where the archive file will be written/read by default.
- `directory` (string, default: `"~"`): Working directory used for tar with `-C`.
- `create_on_stop` (bool, default: `false`): If true, registers a `run_on_stop` script that invokes the create wrapper on workspace stop.
- `extract_on_start` (bool, default: `false`): If true, the installer waits up to `extract_wait_timeout_seconds` for the archive path to appear and extracts it on start.
- `extract_wait_timeout_seconds` (number, default: `300`): Timeout for `extract_on_start`.

## Outputs

- `archive_path` (string): Full archive path computed as `output_dir/archive_name + extension`, where the extension comes from `compression`:
  - `.tar.gz` for `gzip`
  - `.tar.zst` for `zstd`
  - `.tar` for `none`

## Command usage

The installer writes the following files:

- `$CODER_SCRIPT_DATA_DIR/archive-lib.sh`
- `$CODER_SCRIPT_BIN_DIR/coder-archive-create`
- `$CODER_SCRIPT_BIN_DIR/coder-archive-extract`

Create usage:

```console
coder-archive-create [OPTIONS] [PATHS...]
  -c, --compression <gzip|zstd|none>   Compression algorithm (default from module)
  -C, --directory <DIRECTORY>          Change to directory for archiving (default from module)
  -f, --file <ARCHIVE>                 Output archive file (default from module)
  -h, --help                           Show help
```

Extract usage:

```console
coder-archive-extract [OPTIONS]
  -c, --compression <gzip|zstd|none>   Compression algorithm (default from module)
  -C, --directory <DIRECTORY>          Extract into directory (default from module)
  -f, --file <ARCHIVE>                 Archive file to extract (default from module)
  -h, --help                           Show help
```

Examples:

- Use Terraform defaults:

  ```
  coder-archive-create
  ```

- Override compression and output file at runtime:

  ```
  coder-archive-create --compression zstd --file /tmp/backups/archive.tar.zst
  ```

- Add extra paths on the fly (in addition to the Terraform defaults):

  ```
  coder-archive-create /etc/hosts
  ```

- Extract an archive into a directory:

  ```
  coder-archive-extract --file /tmp/backups/archive.tar.gz --directory /tmp/restore
  ```
