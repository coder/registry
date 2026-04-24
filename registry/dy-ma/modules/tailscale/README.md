---
display_name: Tailscale
description: Joins the workspace to your Tailscale network using OAuth or a pre-generated auth key.
icon: ../../../../.icons/tailscale.svg
verified: false
tags: [networking, tailscale]
---

# Tailscale

Installs [Tailscale](https://tailscale.com) and joins the workspace to your tailnet on start. Supports kernel and userspace networking, and works with both Tailscale's hosted service and self-hosted [Headscale](https://headscale.net).

```tf
module "tailscale" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/dy-ma/tailscale/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  oauth_client_id     = "kFvxxxxxxxxxx"
  oauth_client_secret = "tskey-client-xxxx"
}
```

> Do not hardcode credentials in your template. Pass them via Terraform variables, `TF_VAR_*` environment variables, or your preferred secrets manager.
>
> **Creating OAuth credentials:** In the Tailscale admin console go to **Settings → OAuth Clients** and create a client with the `auth_keys` scope and the ACL tags your workspaces will use (e.g. `tag:coder-workspace`).

## Examples

### VM workspace (persistent identity)

For VMs or long-lived containers where you want the node to keep its identity across workspace stop/start:

```tf
module "tailscale" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/dy-ma/tailscale/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  oauth_client_id     = "kFvxxxxxxxxxx"
  oauth_client_secret = "tskey-client-xxxx"
  ephemeral           = false
  networking_mode     = "kernel"
  state_dir           = "/var/lib/tailscale"
}
```

### Ephemeral pod / unprivileged container

For Kubernetes pods or Docker containers without access to `/dev/net/tun`. Userspace mode exposes a SOCKS5 proxy on port `1080` and an HTTP proxy on port `3128` for outbound tailnet access:

```tf
module "tailscale" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/dy-ma/tailscale/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  oauth_client_id     = "kFvxxxxxxxxxx"
  oauth_client_secret = "tskey-client-xxxx"
  ephemeral           = true
  networking_mode     = "userspace"
  state_dir           = "/tmp/tailscale-state"
}
```

### Pre-generated auth key

If you prefer to manage key rotation externally, pass an auth key directly and skip the OAuth flow:

```tf
module "tailscale" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/dy-ma/tailscale/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  auth_key = "tskey-auth-xxxx"
}
```

### Headscale

Point `tailscale_api_url` at your Headscale server and pass a pre-generated auth key:

```tf
module "tailscale" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/dy-ma/tailscale/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  auth_key          = "tskey-auth-xxxx"
  tailscale_api_url = "https://headscale.example.com"
}
```

### Tailscale SSH

Enable Tailscale SSH so tailnet members can reach workspaces directly without managing keys. The `tags` variable (default `["tag:coder-workspace"]`) controls which ACL tag the node advertises — override it if your policy uses a different tag.

```tf
module "tailscale" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/dy-ma/tailscale/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  oauth_client_id     = "kFvxxxxxxxxxx"
  oauth_client_secret = "tskey-client-xxxx"
  ssh                 = true
  tags                = ["tag:coder-workspace"] # override if needed
}
```

You also need to allow SSH access in your [Tailscale ACL policy](https://login.tailscale.com/admin/acls). At minimum, add an SSH rule and a traffic rule for the tag:

```json
{
  "tagOwners": {
    "tag:coder-workspace": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:coder-workspace:*"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["tag:coder-workspace"],
      "users": ["autogroup:nonroot", "root"]
    }
  ]
}
```

### Extra flags

Pass any additional `tailscale up` flags not covered by dedicated variables:

```tf
module "tailscale" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/dy-ma/tailscale/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  oauth_client_id     = "kFvxxxxxxxxxx"
  oauth_client_secret = "tskey-client-xxxx"
  extra_flags         = "--exit-node=100.64.0.1"
}
```
