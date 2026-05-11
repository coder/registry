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
  icon_url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/tailscale-light.svg"
  hostname = var.hostname != "" ? var.hostname : data.coder_workspace.me.name
  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    TAILSCALE_API_URL   = var.tailscale_api_url
    AUTH_KEY            = nonsensitive(base64encode(var.auth_key))
    OAUTH_CLIENT_ID     = nonsensitive(base64encode(var.oauth_client_id))
    OAUTH_CLIENT_SECRET = nonsensitive(base64encode(var.oauth_client_secret))
    TAILNET             = var.tailnet
    HOSTNAME            = local.hostname
    TAGS_JSON           = base64encode(jsonencode(var.tags))
    TAGS_CSV            = join(",", var.tags)
    EPHEMERAL           = tostring(var.ephemeral)
    PREAUTHORIZED       = tostring(var.preauthorized)
    NETWORKING_MODE     = var.networking_mode
    SOCKS5_PORT         = var.socks5_proxy_port
    HTTP_PROXY_PORT     = var.http_proxy_port
    ACCEPT_DNS          = tostring(var.accept_dns)
    ACCEPT_ROUTES       = tostring(var.accept_routes)
    ADVERTISE_ROUTES    = join(",", var.advertise_routes)
    SSH                 = tostring(var.ssh)
    EXTRA_FLAGS         = var.extra_flags
    STATE_DIR           = var.state_dir
  })
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "auth_key" {
  description = <<-EOF
    A pre-generated Tailscale or Headscale auth key. When set, the OAuth
    client credentials flow is skipped and this key is passed directly to
    tailscale up. Use this for Headscale or when you prefer to manage key
    rotation externally (e.g. via Vault).

    Either auth_key or both oauth_client_id and oauth_client_secret must be
    provided. If auth_key is set, oauth_client_id and oauth_client_secret are
    ignored.
  EOF
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_api_url" {
  description = <<-EOF
    Base URL of the control server. Defaults to Tailscale's hosted service.
    Set this to your own server URL (e.g. a Headscale instance).
  EOF
  type        = string
  default     = "https://api.tailscale.com"
}

variable "oauth_client_id" {
  description = "Tailscale OAuth client ID with the auth_keys scope."
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_client_secret" {
  description = "Tailscale OAuth client secret with the auth_keys scope."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailnet" {
  description = "Tailnet name. Defaults to '-' which resolves to the default tailnet for the Oauth client."
  type        = string
  default     = "-"
}

variable "hostname" {
  description = "Hostname to register in the tailnet. Leave blank to use the workspace name."
  type        = string
  default     = ""
}

variable "tags" {
  description = "ACL tags to apply to the node."
  type        = list(string)
  default     = ["tag:coder-workspace"]
  validation {
    condition     = alltrue([for t in var.tags : startswith(t, "tag:")])
    error_message = "All tags must start with \"tag:\"."
  }
}

variable "ephemeral" {
  description = "Whether to register the node as ephemeral."
  type        = bool
  default     = true
}

variable "preauthorized" {
  description = "Skip manual device approval when the node joins the tailnet"
  type        = bool
  default     = true
}

variable "networking_mode" {
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
  type        = string
  default     = "auto"
  validation {
    condition     = contains(["auto", "kernel", "userspace"], var.networking_mode)
    error_message = "networking_mode must be one of: auto, kernel, userspace."
  }
}

variable "socks5_proxy_port" {
  description = <<-EOF
    Port for the SOCKS5 proxy exposed by tailscaled in userspace mode.
    Set to 0 to disable. Only active when networking_mode resolves to userspace.
  EOF
  type        = number
  default     = 1080
}

variable "http_proxy_port" {
  description = <<-EOF
    Port for the HTTP proxy exposed by tailscaled in userspace mode.
    Set to 0 to disable. Only active when networking_mode resolves to userspace.
  EOF
  type        = number
  default     = 3128
}

variable "accept_dns" {
  description = "Accept DNS configuration from the tailnet (MagicDNS)."
  type        = bool
  default     = true
}

variable "accept_routes" {
  description = "Accept subnet routes advertised by other nodes in the tailnet"
  type        = bool
  default     = false
}

variable "advertise_routes" {
  description = "CIDR ranges this workspace should advertise as subnet routes."
  type        = list(string)
  default     = []
}

variable "ssh" {
  description = "Enable Tailscale SSH. Allows other tailnet nodes to ssh into this workspace as defined by your tailnet policy."
  type        = bool
  default     = false
}

variable "extra_flags" {
  description = <<-EOF
    Additional flags to append to the `tailscale up` command verbatim.
    Use this for any options not covered by dedicated variables, e.g.
    `--exit-node=100.x.y.z` or `--shields-up`.
  EOF
  type        = string
  default     = ""
}

variable "state_dir" {
  description = <<-EOF
    Directory for tailscaled state files. Leave empty to use tailscaled's
    default location. Override to a persistent path on VMs (e.g.
    /var/lib/tailscale) or a non-persistent path on ephemeral pods
    (e.g. /tmp/tailscale-state).
  EOF
  type        = string
  default     = ""
}

variable "pre_install_script" {
  description = "Custom script to run before installing Tailscale. Use this to order this module after another module's install pipeline."
  type        = string
  default     = null
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id         = var.agent_id
  module_directory = "$HOME/.coder-modules/dy-ma/tailscale"

  display_name_prefix = "Tailscale"
  icon                = local.icon_url

  pre_install_script = var.pre_install_script
  install_script     = file("${path.module}/install.sh")
  start_script       = local.start_script
}

output "hostname" {
  description = "Hostname registered in tailnet."
  value       = local.hostname
}

output "state_dir" {
  description = "Directory where tailscaled state is persisted. Empty string means tailscaled's default location."
  value       = var.state_dir
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}