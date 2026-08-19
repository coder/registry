---
display_name: Supabase CLI
description: Install Supabase CLI and configure authentication via Coder external auth or access token
icon: ../../../../.icons/supabase.svg
verified: false
tags: [supabase, database, cli, helper]
---

# Supabase CLI

Installs the [Supabase CLI](https://supabase.com/docs/guides/cli) and configures authentication. The CLI is available immediately in your workspace without manual login flows.

```tf
module "supabase" {
  source   = "registry.coder.com/coder/supabase/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Authentication

Choose **one** of the following authentication methods:

### Option 1: Personal Access Token

Generate a token at [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) and pass it to the module via the `access_token` variable with `use_external_auth = false`.

### Option 2: Coder External Auth (OAuth)

Configure Supabase as an [external auth provider](https://coder.com/docs/admin/external-auth) in your Coder deployment. Users authenticate via OAuth when launching a workspace.

Required Coder environment variables:

```bash
CODER_EXTERNAL_AUTH_0_ID=supabase
CODER_EXTERNAL_AUTH_0_TYPE=custom
CODER_EXTERNAL_AUTH_0_CLIENT_ID=<your-client-id>
CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=<your-client-secret>
CODER_EXTERNAL_AUTH_0_AUTH_URL=https://api.supabase.com/v1/oauth/authorize
CODER_EXTERNAL_AUTH_0_TOKEN_URL=https://api.supabase.com/v1/oauth/token
CODER_EXTERNAL_AUTH_0_SCOPES=all
CODER_EXTERNAL_AUTH_0_DISPLAY_NAME=Supabase
CODER_EXTERNAL_AUTH_0_DISPLAY_ICON=/icon/supabase.svg
```

Create your OAuth app in the [Supabase Dashboard](https://supabase.com/dashboard/account/oauth-apps) under "OAuth Apps" → "Published apps". Set the redirect URI to `https://<your-coder-url>/external-auth/supabase/callback`.

## Usage

### With Personal Access Token

```tf
module "supabase" {
  source            = "registry.coder.com/coder/supabase/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  use_external_auth = false
  access_token      = var.supabase_token # From Terraform variable or secret
}
```

### With External Auth (OAuth)

```tf
module "supabase" {
  source            = "registry.coder.com/coder/supabase/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  use_external_auth = true
  # external_auth_id = "supabase"  # Default; change if your provider has a different ID
}
```

### With Project Dashboard Link

```tf
module "supabase" {
  source            = "registry.coder.com/coder/supabase/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  use_external_auth = false
  access_token      = var.supabase_token
  project_ref       = "abcdefghijklmnop" # Links dashboard button directly to this project
}
```

### With Custom Install Method

```tf
module "supabase" {
  source         = "registry.coder.com/coder/supabase/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  install_method = "binary" # Force binary install instead of detect
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

## Dashboard App

The module adds a **Supabase** button to your workspace that links to the Supabase dashboard:

- **Without `project_ref`**: Links to [supabase.com/dashboard](https://supabase.com/dashboard) (project list)
- **With `project_ref`**: Links directly to your project's dashboard

Find your project reference in the Supabase dashboard URL: `https://supabase.com/dashboard/project/<project_ref>`

## Environment Variables

The module sets the following environment variables in your workspace:

| Variable                | Description                                        |
| ----------------------- | -------------------------------------------------- |
| `SUPABASE_ACCESS_TOKEN` | Personal access token for CLI authentication       |
| `SUPABASE_DB_PASSWORD`  | Remote Postgres password for `supabase link` in CI |

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
