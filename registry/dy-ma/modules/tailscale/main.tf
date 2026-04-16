terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

data "coder_workspace" "me" {}

locals {
  icon_url  = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/tailscale.svg"
  hostname  = var.hostname != "" ? var.hostname : data.coder_workspace.me.name
  tags_json = jsonencode(var.tags)
  tags_csv  = join(",", var.tags)
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "auth_key" {
  type      = string
  sensitive = true
  default   = ""
  description = <<-EOF
    A pre-generated Tailscale or Headscale auth key. When set, the OAuth
    client credentials flow is skipped and this key is passed directly to
    tailscale up. Use this for Headscale or when you prefer to manage key
    rotation externally (e.g. via Vault).

    Either auth_key or both oauth_client_id and oauth_client_secret must be
    provided. If auth_key is set, oauth_client_id and oauth_client_secret are
    ignored.
  EOF
}

variable "tailscale_api_url" {
  type    = string
  default = "https://api.tailscale.com"
  description = <<-EOF
    Base URL of the control server. Defaults to Tailscale's hosted service.
    Set this to your own server URL (e.g. a Headscale instance).
  EOF
}

variable "oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
  description = "Tailscale OAuth client ID with the auth_keys scope."
}

variable "oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
  description = "Tailscale OAuth client secret with the auth_keys scope."
}

variable "tailnet" {
  type = string
  default = "-"
  description = "Tailnet name. Defaults to '-' which resolves to the default tailnet for the Oauth client."
}

variable "hostname" {
  type = string
  default = ""
  description = "Hostname to register in the tailnet. Leave blank to use the workspace name."
}

variable "tags" {
  type = list(string)
  default = [ "tag:coder-workspace" ]
  description = "ACL tags to apply to the node."
  validation {
    condition = alltrue([for t in var.tags : startswith(t, "tag:")])
    error_message = "All tags must start with \"tag:\"."
  }
}

variable "ephemeral" {
  type = bool
  default = true
  description = "Whether to register the node as ephemeral."
}

variable "preauthorized" {
  type = bool
  default = true
  description = "Skip manual device approval when the node joins the tailnet"
}

variable "networking_mode" {
  type = string
  default = "auto"
  description = <<-EOF
    Tailscale networking mode.

    auto      — detect from environment. Uses kernel networking if
                /dev/net/tun is accessible, userspace otherwise.
    kernel    — force kernel networking (requires TUN device). Suitable
                for VMs and privileged containers.
    userspace — force userspace networking. Required for unprivileged
                containers. Enables SOCKS5/HTTP proxies for outbound
                tailnet access.
  EOF
  validation {
    condition = contains(["auto", "kernel", "userspace"], var.networking_mode)
    error_message = "networking_mode must be one of: auto, kernel, userspace."
  }
}

variable "socks5_proxy_port" {
  type = number
  default = 1080
  description = <<-EOF
    Port for the SOCKS5 proxy exposed by tailscaled in userspace mode.
    Set to 0 to disable. Only active when networking_mode resolves to userspace.
  EOF
}

variable "http_proxy_port" {
  type = number
  default = 3128
  description = <<-EOF
    Port for the HTTP proxy exposed by tailscaled in userspace mode.
    Set to 0 to disable. Only active when networking_mode resolves to userspace.
  EOF
}

variable "accept_dns" {
  type = bool
  default = true
  description = "Accept DNS configuration from the tailnet (MagicDNS)."
}

variable "accept_routes" {
  type = bool
  default = false
  description = "Accept subnet routes advertised by other nodes in the tailnet"
}

variable "advertise_routes" {
  type = list(string)
  default = []
  description = "CIDR ranges this workspace should advertise as subnet routes."
}

variable "ssh" {
  type = bool
  default = false
  description = "Enable Tailscale SSH. Allows other tailnet nodes to ssh into this workspace as defined by your tailnet policy."
}


variable "extra_flags" {
  type    = string
  default = ""
  description = <<-EOF
    Additional flags to append to the `tailscale up` command verbatim.
    Use this for any options not covered by dedicated variables, e.g.
    `--exit-node=100.x.y.z` or `--shields-up`.
  EOF
}

variable "state_dir" {
  type    = string
  default = ""
  description = <<-EOF
    Directory for tailscaled state files. Leave empty to use tailscaled's
    default location. Override to a persistent path on VMs (e.g.
    /var/lib/tailscale) or a non-persistent path on ephemeral pods
    (e.g. /tmp/tailscale-state).
  EOF
}

resource "coder_script" "install_tailscale" {
  agent_id     = var.agent_id
  display_name = "Tailscale"
  icon         = local.icon_url
  script = templatefile("${path.module}/run.sh", {
    TAILSCALE_API_URL   = var.tailscale_api_url
    AUTH_KEY            = var.auth_key
    OAUTH_CLIENT_ID     = var.oauth_client_id
    OAUTH_CLIENT_SECRET = var.oauth_client_secret
    TAILNET             = var.tailnet
    HOSTNAME            = local.hostname
    TAGS_JSON           = local.tags_json
    TAGS_CSV            = local.tags_csv
    EPHEMERAL           = var.ephemeral
    PREAUTHORIZED       = var.preauthorized
    NETWORKING_MODE     = var.networking_mode
    SOCKS5_PORT         = var.socks5_proxy_port
    HTTP_PROXY_PORT     = var.http_proxy_port
    ACCEPT_DNS          = var.accept_dns
    ACCEPT_ROUTES       = var.accept_routes
    ADVERTISE_ROUTES    = join(",", var.advertise_routes)
    SSH                 = var.ssh
    EXTRA_FLAGS         = var.extra_flags
    STATE_DIR           = var.state_dir
  })
  run_on_start = true
  run_on_stop  = false
}

output "hostname" {
  description = "Hostname registered in tailnet."
  value       = local.hostname
}

output "state_dir" {
  description = "Directory where tailscaled state is persisted. Empty string means tailscaled's default location."
  value       = var.state_dir
}