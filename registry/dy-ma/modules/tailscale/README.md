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
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
```

Add the corresponding variables to your template so Terraform can receive the credentials:

```tf
variable "tailscale_oauth_client_id" {
  type      = string
  sensitive = true
}

variable "tailscale_oauth_client_secret" {
  type      = string
  sensitive = true
}
```

Set them as [template variables](https://coder.com/docs/admin/templates/managing-templates/variables) in the Coder dashboard, or via environment variables when running `terraform apply` locally:

```sh
export TF_VAR_tailscale_oauth_client_id="tskey-client-xxxx"
export TF_VAR_tailscale_oauth_client_secret="tskey-secret-xxxx"
```

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
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
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
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  ephemeral           = true
  networking_mode     = "userspace"
  state_dir           = "/tmp/tailscale-state"
}
```

### Pre-generated auth key

If you prefer to manage key rotation externally, pass an auth key directly and skip the OAuth flow:

```tf
variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

module "tailscale" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/dy-ma/tailscale/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  auth_key = var.tailscale_auth_key
}
```

### Headscale

Point `tailscale_api_url` at your Headscale server and use a pre-generated auth key (Headscale does not support the Tailscale OAuth flow):

```tf
module "tailscale" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/dy-ma/tailscale/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  auth_key          = var.tailscale_auth_key
  tailscale_api_url = "https://headscale.example.com"
}
```
