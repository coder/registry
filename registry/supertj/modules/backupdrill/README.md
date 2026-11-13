---
display_name: BackupDrill CLI
description: Install the backupdrill CLI to back up Supabase to your own S3 bucket and test-restore the backups
icon: ../../../../.icons/backupdrill.svg
verified: false
tags: [supabase, backup, postgres, database, cli]
---

# BackupDrill CLI

Installs [the backupdrill CLI](https://backupdrill.com/docs/cli) in your workspace. backupdrill is an open-source command-line tool that backs up a Supabase project's Postgres database, and optionally its Storage files, to an S3, R2 or B2 bucket you own. Its `drill` command restores a backup into a throwaway Postgres container to check that it actually comes back.

```tf
module "backupdrill" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/supertj/backupdrill/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

By default the module installs the newest 2.x release from npm, so new workspaces pick up 2.x releases without a module update. It installs into `$HOME/.coder-modules/supertj/backupdrill` and doesn't need root. It doesn't install `pg_dump` and takes no credentials.

## Requirements

- Node.js 20 or newer with npm on the workspace `PATH`. On an older Node.js, npm refuses the install. A Node.js installed with nvm is found as well. If npm is missing, the install script prints a message and exits without an error, so the workspace starts as usual.
- `pg_dump` for `backup`, with a major version at least as new as your Supabase Postgres. Install it in the image (for example `postgresql-client-<major>` from the PostgreSQL apt repository), or point `BACKUPDRILL_PG_DUMP` at the binary.
- For `drill`: `pg_restore` (same version rule) and a Docker daemon the workspace can reach, which runs the throwaway Postgres.

## Credentials

backupdrill reads its settings from `BACKUPDRILL_*` environment variables. At minimum it needs the database connection string (the Session pooler string from the Supabase dashboard), the bucket name and the bucket's access keys. You can export them in the workspace terminal or keep them in a gitignored env file that you source.

If every workspace built from a template should back up the same project, pass the values in from sensitive template variables with `coder_env`, which keeps them out of the template source:

```tf
variable "backupdrill_database_url" {
  type      = string
  sensitive = true
}

resource "coder_env" "backupdrill_database_url" {
  agent_id = coder_agent.main.id
  name     = "BACKUPDRILL_DATABASE_URL"
  value    = var.backupdrill_database_url
}
```

Do the same for `BACKUPDRILL_S3_BUCKET`, `BACKUPDRILL_S3_ACCESS_KEY_ID` and `BACKUPDRILL_S3_SECRET_ACCESS_KEY`, plus `BACKUPDRILL_S3_ENDPOINT` for R2 or B2. The [backupdrill docs](https://backupdrill.com/docs/cli) cover the remaining variables and a config file option.

## Usage

```bash
backupdrill estimate --plan pro # egress a backup would add to your Supabase bill
backupdrill backup              # database (and Storage files, if configured) to your bucket
backupdrill drill               # restore the latest backup into a throwaway Postgres and check it
```

## Pin a version

`backupdrill_version` takes a major (`"2"`, the default), a major.minor such as `"2.7"`, an exact version, or `"latest"`.

```tf
module "backupdrill" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/supertj/backupdrill/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  backupdrill_version = "2.7.1"
}
```

## Pre-installed CLI and restarts

If `backupdrill` is already on `PATH` when the workspace starts (baked into the image, say) and its version matches `backupdrill_version`, the module skips the install and downloads nothing. A copy that the module installed on an earlier start is reused the same way.

With the default `"2"`, any 2.x counts as a match, so a workspace that keeps its home directory stays on the 2.x it installed first. To move it to the newest 2.x, delete `$HOME/.coder-modules/supertj/backupdrill/npm-global` and restart the workspace.

## Install from a mirror

```tf
module "backupdrill" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/supertj/backupdrill/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.main.id
  npm_registry_url = "https://npm.example.com/repository/npm/"
}
```

## Network access

| Endpoint                                               | Purpose                                         | When                            |
| ------------------------------------------------------ | ----------------------------------------------- | ------------------------------- |
| `registry.npmjs.org`, or `npm_registry_url` if set     | Download the CLI                                | Install                         |
| Your Supabase project's database and Storage endpoints | Read the data to back up, write during restores | `backup`, `estimate`, `restore` |
| Your S3, R2 or B2 bucket                               | Store and read snapshots                        | `backup`, `drill`, `restore`    |
| Docker Hub (`postgres`, `pgvector/pgvector`)           | Pull the throwaway Postgres image               | `drill`                         |
| Your Healthchecks.io ping URL, if set                  | Report whether a run passed                     | `backup`, `drill`               |

backupdrill doesn't send anything to BackupDrill's own servers.

## Logs

The install script writes to `$HOME/.coder-modules/supertj/backupdrill/logs/install.log`.
