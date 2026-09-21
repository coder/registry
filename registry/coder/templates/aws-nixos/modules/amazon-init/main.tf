# Everything that has to happen because this is a NixOS AMI on EC2, and
# nothing that has to happen because it is Nix or because it is Coder.
#
# The NixOS AMI does not run cloud-init. It runs amazon-init.service, which
# reads /etc/ec2-metadata/user-data and execs it as a shell script when it
# begins with `#!` -- after multi-user.target, on every boot. That is the only
# hook this platform offers, so it has to carry the agent handoff, the
# workspace facts and the rebuild, and it has to be idempotent.

terraform {
  required_version = ">= 1.0"
}

variable "flake_ref" {
  description = "Git remote to clone into the checkout, as `git clone` understands it."
  type        = string
}

variable "flake_branch" {
  description = "Branch to track in that remote."
  type        = string
}

variable "flake_attr" {
  description = "`nixosConfigurations` attribute to build, architecture already resolved."
  type        = string
}

variable "access_url" {
  description = "Deployment access URL the agent and the log API are reached on."
  type        = string
}

variable "agent_token" {
  description = "Agent token. Written to /run/coder/agent.env at 0600 on a tmpfs and never passed into Nix."
  type        = string
  sensitive   = true
}

variable "agent_init_script" {
  description = "`coder_agent.init_script`, run verbatim once the rebuild has finished."
  type        = string
  sensitive   = true
}

variable "log_source_id" {
  description = "Log source the rebuild streams to. Must be stable across builds."
  type        = string
}

variable "workspace_name" {
  description = "Workspace name, published in /run/coder/workspace.json."
  type        = string
}

variable "hostname" {
  description = "Hostname to set on the instance."
  type        = string
}

variable "owner" {
  description = "Workspace owner's username."
  type        = string
}

variable "owner_name" {
  description = "Workspace owner's full name."
  type        = string
}

variable "owner_email" {
  description = "Workspace owner's email address."
  type        = string
}

variable "log_library" {
  description = <<-EOT
    Contents of the shell library providing `coder_log`, sourced into the boot
    script. Passed in rather than read here so the same copy is shared with
    the template's other entrypoints.
  EOT
  type        = string
}

variable "lifecycle_library" {
  description = "Contents of the Nix lifecycle shell library, sourced into the boot script."
  type        = string
}

locals {
  bootstrap = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    LOG_SH              = var.log_library
    LIFECYCLE_SH        = var.lifecycle_library
    ARG_FLAKE_REF       = var.flake_ref
    ARG_FLAKE_BRANCH    = var.flake_branch
    ARG_FLAKE_ATTR      = var.flake_attr
    ARG_ACCESS_URL      = var.access_url
    ARG_AGENT_TOKEN     = var.agent_token
    ARG_INIT_SCRIPT_B64 = base64encode(var.agent_init_script)
    ARG_LOG_SOURCE_ID   = var.log_source_id
    ARG_HOSTNAME        = var.hostname
    ARG_WORKSPACE_NAME  = var.workspace_name
    ARG_OWNER           = var.owner
    # base64 because a full name may contain quotes and is interpolated into
    # a shell string.
    ARG_OWNER_NAME_B64 = base64encode(var.owner_name)
    ARG_OWNER_EMAIL    = var.owner_email
  })

  # EC2 caps user-data at 16 KiB, and the boot script plus its two libraries
  # plus the agent init script come to roughly 19 KiB. So user-data is a
  # six-line self-extracting wrapper around a compressed copy.
  #
  # This is transparent to the NixOS AMI: amazon-init only inspects the first
  # two bytes for `#!` before exec'ing the blob, and it has no decompression
  # step of its own. Extracting to a fixed path also means the real script is
  # on disk when something needs debugging.
  user_data = <<-SH
    #!/usr/bin/env bash
    set -eu
    install -d -m 0700 /run/coder
    base64 -d <<'CODER_PAYLOAD' | gzip -dc >/run/coder/bootstrap.sh
    ${base64gzip(local.bootstrap)}
    CODER_PAYLOAD
    exec bash /run/coder/bootstrap.sh
  SH
}

output "user_data" {
  description = "Rendered EC2 user-data. Sensitive: it carries the agent token."
  value       = local.user_data
  sensitive   = true
}

output "user_data_bytes" {
  description = "Size of the rendered user-data, for the caller's 16 KiB precondition."
  value       = nonsensitive(length(local.user_data))
}

output "bootstrap_path" {
  description = "Where the wrapper extracts the real boot script on the instance."
  value       = "/run/coder/bootstrap.sh"
}
