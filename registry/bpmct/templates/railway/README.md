---
display_name: Railway (via GraphQL)
description: Coder workspaces backed by Railway services, provisioned via direct GraphQL calls (no community Terraform provider).
icon: ../../../../.icons/railway.svg
verified: false
tags: [railway, cloud, container, docker]
---

# Railway (via GraphQL)

Each Coder workspace is a fully isolated [Railway](https://railway.com) project running a container built from a public image on GHCR. Every workspace becomes a first-class Railway project (its own environment, its own volumes, its own service token), which sets up a natural extension point: the workspace user can manage further Railway resources inside their own project via the [Railway CLI](https://docs.railway.com/reference/cli-api).

[![Demo: Railway + Coder workspaces](https://cdn.loom.com/sessions/thumbnails/92a59e1f379c4b6bb8869f14df5e837d-49d50ac4ed07b42c.gif)](https://www.loom.com/share/92a59e1f379c4b6bb8869f14df5e837d)
_Demo (Loom, ~5 min)_

> [!NOTE]
> The Loom above was recorded before startup was optimized. The demo shows a per-start Docker build (~62s median). This template now uses `serviceInstanceUpdate(source: { image })` against a pre-built image (`ghcr.io/bpmct/railway-coder-workspace:latest`), so median start time is ~6s. The rest of the flow in the demo (workspace creation, project isolation, Railway CLI) still applies.

## Why direct GraphQL instead of the Terraform provider

The community [`terraform-community-providers/railway`](https://github.com/terraform-community-providers/terraform-provider-railway) provider is a great starting point, but hits two blocking issues for a Coder template that has to run reliably under stress:

1. **Volume creation is racy.** `railway_volume` can write to a service before the service is fully attached, and Railway rejects `volumeCreate` on services that have had deployments. Terraform's implicit ordering does not respect Railway's API contract here.
2. **`variableUpsert` triggers extra deploys.** Every env var write during workspace start races a redeploy that intermittently fails with "Cannot redeploy without a snapshot" (just after `serviceDisconnect`) or "Cannot redeploy yet, please wait for the original deployment to finish building" (during the first second after a `deploymentCancel`).

This template bypasses the provider entirely for the Railway operations and calls the [Railway public API](https://docs.railway.com/reference/public-api) directly with `curl`. Key fixes that keep the reliability suite green:

- **`skipDeploys: true`** on `variableUpsert`. An undocumented flag that tells Railway to persist the value without enqueuing a redeploy. The subsequent `serviceInstanceDeployV2` is what actually deploys, and it picks up the freshly-set variables.
- **Explicit `volumeCreate` before any deployment activity**, with backoff on the "creating volumes too quickly" rate limit.
- **`serviceInstanceUpdate(source: { image })` + `serviceInstanceDeployV2`** for the image deploy, rather than `serviceConnect` (which builds from a repo on every start).

See [bpmct/coder-railway](https://github.com/bpmct/coder-railway) for the full write-up, the reliability suite, and three other variants (Terraform-provider-based, hybrid, and Railway-CLI-based) that were tried along the way.

## Prerequisites

### 1. Railway API token

Create a Railway account/team token at [railway.com/account/tokens](https://railway.com/account/tokens). It must be an account or team token (not a project token) so that the template can call `projectCreate`.

### 2. Push the template with the token

```sh
coder templates push railway --directory . \
  --variable railway_token=YOUR_RAILWAY_TOKEN
```

The Railway master token is stored as a Terraform variable at the template level and is never exposed to workspace users. If `enable_project_management` is set to `true`, each workspace also gets its own project-scoped Railway token (a much narrower blast radius) injected as `$RAILWAY_TOKEN` inside the workspace, and the Railway CLI is auto-installed and pre-authenticated:

```sh
coder templates push railway --directory . \
  --variable railway_token=YOUR_RAILWAY_TOKEN \
  --variable enable_project_management=true
```

## Usage

Create a workspace from the `railway` template. The only end-user parameter is:

- **Region**: US West, US East, EU West, Asia Southeast.

Everything else (project, service, volume, env vars, image source, first deploy) happens under the hood via GraphQL.

## Architecture

For each workspace, this template provisions on Railway:

- **Project** (`coder-<owner>-<workspace>`, one per workspace).
- **Service** (`workspace`) pinned to the image in `workspace_image`.
- **Volume** persisting `/home/coder`, survives stop/start.
- **Env vars** on the service: `CODER_AGENT_TOKEN`, `CODER_INIT_SCRIPT_B64`, `RAILWAY_RUN_UID=0`.
- Optionally, a **project-scoped Railway token** exposed to the workspace as `$RAILWAY_TOKEN`.

Persistent (survive stop/start): project, service, volume, project token. Ephemeral (per start): env vars, image deploy.

### Custom workspace image

The default image is `ghcr.io/bpmct/railway-coder-workspace:latest`, which is `codercom/enterprise-base:ubuntu` plus a small entrypoint that fixes Railway volume ownership, decodes `CODER_INIT_SCRIPT_B64`, and runs the Coder agent as the `coder` user. The Dockerfile and entrypoint are vendored in this template under [`build/`](./build) so you can read, fork, or extend them without leaving the registry:

- [`build/Dockerfile`](./build/Dockerfile) - 10 lines, thin layer on `codercom/enterprise-base:ubuntu`.
- [`build/entrypoint.sh`](./build/entrypoint.sh) - Railway volume `chown`, skeleton seed, `CODER_INIT_SCRIPT_B64` decode + drop to `coder`.

**Adding your own tools:** the default image is deliberately minimal, so most teams will want to extend it. Two patterns:

1. **Extend the default image** (recommended for most cases). Write a Dockerfile that starts `FROM ghcr.io/bpmct/railway-coder-workspace:latest` and layer whatever you need on top. Entrypoint and Coder agent wiring are inherited, so you only touch what you actually need.

   ```dockerfile
   FROM ghcr.io/bpmct/railway-coder-workspace:latest
   USER root
   RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client redis-tools \
    && rm -rf /var/lib/apt/lists/*
   ```

2. **Duplicate `build/` and build from a different base**, if you need to swap the base image entirely (e.g. `codercom/example-universal:ubuntu`, an internal golden image, or a non-Ubuntu distro). Copy [`build/entrypoint.sh`](./build/entrypoint.sh) verbatim - the image contract that the template relies on (volume chown, `CODER_INIT_SCRIPT_B64` decode, drop to `coder` user) lives in that entrypoint, not in the base image.

Build, push to any registry, and point the template at it:

```sh
coder templates push railway --directory . \
  --variable railway_token=YOUR_RAILWAY_TOKEN \
  --variable workspace_image=ghcr.io/yourorg/your-image:tag
```

For private registries, also set `image_registry_username` and `image_registry_password`.

The only contract the template requires from the image is that its `ENTRYPOINT` consumes:

- `CODER_INIT_SCRIPT_B64`: base64-encoded Coder agent init script.
- `CODER_AGENT_TOKEN`: Coder agent token.
- `RAILWAY_RUN_UID=0`: Railway UID override so the entrypoint can chown the root-owned Railway volume mount before dropping to the workspace user.

## Other Railway approaches

This template ships the GraphQL variant, which is the most reliable of four approaches I tried against the Railway API. The others live in [bpmct/coder-railway/variants/wip/](https://github.com/bpmct/coder-railway/tree/main/variants/wip):

- **`tf-patched`**: Uses the Railway Terraform provider with a small patch and a `trailing_zombie` workaround for the redeploy race.
- **`hybrid`**: Uses `railway_service` from the provider, GraphQL for everything else.
- **`cli`**: Uses the Railway CLI (`railway up`, `railway link`) instead of the provider or GraphQL.

See the [benchmark table](https://github.com/bpmct/coder-railway#benchmarks) for the reliability comparison across variants.

> [!NOTE]
> This template is designed to be a starting point. Edit the Terraform to extend it for your use case.
