---
display_name: Archive
description: Create automated and user-invocable scripts that archive and extract selected files/directories with optional compression (gzip or zstd).
icon: ../../../../.icons/tool.svg
verified: false
tags: [backup, archive, tar, helper]
---

# Archive

This module installs small, robust scripts in your workspace to create and extract tar archives from a list of files and directories. It supports gzip, zstd, or no compression. The create command prints only the resulting archive path to stdout; operational logs go to stderr. An optional stop hook can also create an archive automatically when the workspace stops, and an optional start hook can wait for an archive and extract it on start.

- Depends on: `tar` (and `gzip` or `zstd` if you select those compression modes)
- Installed scripts:
  - `$CODER_SCRIPT_BIN_DIR/coder-archive-create`
  - `$CODER_SCRIPT_BIN_DIR/coder-archive-extract`
- Library installed to:
  - `$CODER_SCRIPT_DATA_DIR/archive-lib.sh`
- On start (always): installer decodes and writes the library, then generates the wrappers in `$CODER_SCRIPT_BIN_DIR` with Terraform-provided defaults embedded.
- Optional on stop: when enabled, a separate `run_on_stop` script invokes the create command.

## Features

- Create a single `.tar`, `.tar.gz`, or `.tar.zst` containing selected paths.
- Compression algorithms: `gzip`, `zstd`, `none`.
- Defaults for directory, archive path, compression, include/exclude lists come from Terraform and can be overridden at runtime with CLI flags.
- Logs and status messages go to stderr; the create command prints only the final archive path to stdout.
- Strict bash mode and safe invocation of `tar`.
- Optional:
  - `run_on_stop` to create an archive automatically when the workspace stops.
  - `extract_on_start` to wait for an archive to appear and extract it on start (with timeout).

## Usage

Basic example:

    module "archive" {
      count     = data.coder_workspace.me.start_count
      source    = "registry.coder.com/coder/archive/coder"
      version   = "0.0.1"
      agent_id  = coder_agent.example.id

      # Paths to include in the archive (files or directories).
      directory = "/"
      paths     = [
        "/etc/hostname",
        "/etc/hosts",
      ]
    }

Customize compression and output:

    module "archive" {
      count       = data.coder_workspace.me.start_count
      source      = "registry.coder.com/coder/archive/coder"
      version     = "0.0.1"
      agent_id    = coder_agent.example.id

      paths        = ["/etc/hostname"]
      compression  = "zstd"          # "gzip" | "zstd" | "none"
      output_dir   = "/tmp/backup"   # defaults to /tmp
      archive_name = "my-backup"     # base name (extension is inferred from compression)
    }

Enable auto-archive on stop:

    module "archive" {
      count          = data.coder_workspace.me.start_count
      source         = "registry.coder.com/coder/archive/coder"
      version        = "0.0.1"
      agent_id       = coder_agent.example.id

      paths          = ["/etc/hostname"]
      compression    = "gzip"
      create_on_stop = true
    }

Extract on start (optional):

    module "archive" {
      count                          = data.coder_workspace.me.start_count
      source                         = "registry.coder.com/coder/archive/coder"
      version                        = "0.0.1"
      agent_id                       = coder_agent.example.id

      # Where to look for the archive file to extract:
      output_dir                     = "/tmp"
      archive_name                   = "coder-archive"
      compression                    = "gzip"

      extract_on_start               = true
      extract_wait_timeout_seconds   = 300
    }

## Running the scripts

Once the workspace starts, the installer writes:

- `$CODER_SCRIPT_DATA_DIR/archive-lib.sh`
- `$CODER_SCRIPT_BIN_DIR/coder-archive-create`
- `$CODER_SCRIPT_BIN_DIR/coder-archive-extract`

Create usage:

    coder-archive-create [OPTIONS] [PATHS...]
      -c, --compression <gzip|zstd|none>   Compression algorithm (default from module)
      -C, --directory <DIRECTORY>          Change to directory for archiving (default from module)
      -f, --file <ARCHIVE>                 Output archive file (default from module)
      -h, --help                           Show help

Extract usage:

    coder-archive-extract [OPTIONS]
      -c, --compression <gzip|zstd|none>   Compression algorithm (default from module)
      -C, --directory <DIRECTORY>          Extract into directory (default from module)
      -f, --file <ARCHIVE>                 Archive file to extract (default from module)
      -h, --help                           Show help

Examples:

- Use Terraform defaults:

      coder-archive-create

- Override compression and output file at runtime:

      coder-archive-create --compression zstd --file /tmp/backups/archive.tar.zst

- Add extra paths on the fly (in addition to the Terraform defaults):

      coder-archive-create /etc/hosts

- Extract an archive into a directory:

      coder-archive-extract --file /tmp/backups/archive.tar.gz --directory /tmp/restore

Notes:

- Create prints only the final archive path to stdout. All other output (progress, warnings, errors) goes to stderr.
- Extract prints a short message to stdout indicating the destination.
- Exclude patterns from Terraform are forwarded to `tar` using `--exclude`.
- You can run the wrappers with bash xtrace for more debug information:
  - `bash -x "$(which coder-archive-create)" ...`

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

## Requirements

- `tar` is required.
- `gzip` is required if `compression = "gzip"`.
- `zstd` is required if `compression = "zstd"`.

## Behavior

- On start, the installer:
  - Decodes the embedded library to `$CODER_SCRIPT_DATA_DIR/archive-lib.sh`.
  - Generates two wrappers in `$CODER_SCRIPT_BIN_DIR`: `coder-archive-create` and `coder-archive-extract`.
  - Embeds Terraform-provided defaults into the wrappers.
  - If `extract_on_start` is true, the installer sources the library and calls `archive_wait_and_extract`, waiting up to `extract_wait_timeout_seconds` for the file at `archive_path` to appear.
- If `create_on_stop` is true, a `run_on_stop` script is registered that invokes the create command at stop.
- `umask 077` is applied during operations so archives and extracted files are created with restrictive permissions.
