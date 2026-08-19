---
display_name: Supabase CLI
description: Install Supabase CLI and configure authentication via Coder external auth or access token
icon: ../../../../.icons/supabase.svg
verified: false
tags: [supabase, database, cli, helper]
---

# Supabase CLI

Installs the [Supabase CLI](https://supabase.com/docs/guides/cli) and configures authentication. The CLI is available immediately in your workspace without manual login flows.

## Authentication

Choose **one** of the following authentication methods:

### Option 1: Coder External Auth (Recommended)

Configure Supabase as an [external auth provider](https://coder.com/docs/admin/external-auth) in your Coder deployment. Users authenticate via OAuth when launching a workspace.

### Option 2: Personal Access Token

Generate a token at [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) and pass it to the module via the `access_token` variable.

## Usage

### With External Auth

```tf
module "supabase" {
  source   = "registry.coder.com/coder/supabase/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  # external_auth_id = "supabase"  # Default; change if your provider has a different ID
}
```

### With Personal Access Token

```tf
module "supabase" {
  source            = "registry.coder.com/coder/supabase/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  use_external_auth = false
  access_token      = var.supabase_token  # From Terraform variable or secret
}
```

### With Custom Install Method

```tf
module "supabase" {
  source         = "registry.coder.com/coder/supabase/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  install_method = "binary"  # Force binary install instead of detect
}
```

## Installation Methods

The module supports multiple installation methods to work across different workspace environments:

| Method             | Description                  | Platforms      |
| ------------------ | ---------------------------- | -------------- |
| `detect` (default) | Detect best available method | All            |
| `brew`             | Homebrew                     | macOS, Linux   |
| `scoop`            | Scoop package manager        | Windows        |
| `binary`           | Direct binary download       | All (fallback) |

Detection priority: Homebrew → Scoop → Native packages (deb/rpm/apk) → Binary

## Environment Variables

The module sets the following environment variables in your workspace:

| Variable                | Description                                  |
| ----------------------- | -------------------------------------------- |
| `SUPABASE_ACCESS_TOKEN` | Personal access token for CLI authentication |
| `SUPABASE_DB_PASSWORD`  | Database password (if provided)              |

## Common CLI Commands

After workspace start, you can use the Supabase CLI:

```bash
# List your projects
supabase projects list

# Link to a project
supabase link --project-ref <project-id>

# Database operations
supabase db pull          # Pull remote schema
supabase db push          # Push migrations
supabase migration new    # Create migration

# Local development (requires Docker)
supabase start            # Start local stack
supabase stop             # Stop local stack

# Generate TypeScript types
supabase gen types typescript --project-id <id> > types.ts
```

## Logs

Installation logs are stored at:

```
$HOME/.coder-modules/coder/supabase/logs/install.log
```
