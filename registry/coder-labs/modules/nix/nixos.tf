variable "nixos" {
  description = "Apply flake_ref (Git URL, optional git+ prefix and ?ref= branch) and flake_attr (nixosConfigurations attribute) on boot from a root builder agent, then start the main agent. enabled defaults to true; flake_ref, flake_attr, agent_token (the main agent's token) and arch (amd64 or arm64) are required when enabled. order places the builder agent in the UI. runtime_dir holds the main agent handoff, flake_dir holds the checkout, log_dir holds rebuild transcripts and builder logs, and config_override supplies nix.conf settings for the boot rebuild."
  type = object({
    enabled         = optional(bool, true)
    flake_ref       = optional(string)
    flake_attr      = optional(string)
    agent_token     = optional(string)
    arch            = optional(string)
    order           = optional(number, 1)
    runtime_dir     = optional(string, "/run/coder")
    flake_dir       = optional(string, "/etc/nixos")
    log_dir         = optional(string, "/var/log/coder-nixos")
    config_override = optional(any, {})
  })
  default = {}

  validation {
    condition     = !var.nixos.enabled || (var.nixos.flake_ref != null && var.nixos.flake_attr != null)
    error_message = "nixos.flake_ref and nixos.flake_attr are required when nixos.enabled is true."
  }
  validation {
    condition     = !var.nixos.enabled || contains(["amd64", "arm64"], coalesce(var.nixos.arch, "none"))
    error_message = "nixos.arch must be amd64 or arm64 when nixos.enabled is true."
  }
  # A stopped workspace has no agent, so it has no token either.
  validation {
    condition     = !var.nixos.enabled || data.coder_workspace.me.start_count == 0 || nonsensitive(var.nixos.agent_token != null && var.nixos.agent_token != "")
    error_message = "nixos.agent_token is required when nixos.enabled is true."
  }
  validation {
    condition     = startswith(var.nixos.flake_dir, "/") && abspath(var.nixos.flake_dir) != "/"
    error_message = "nixos.flake_dir must be an absolute path other than /."
  }
  validation {
    condition     = startswith(var.nixos.runtime_dir, "/") && abspath(var.nixos.runtime_dir) == var.nixos.runtime_dir && var.nixos.runtime_dir != "/"
    error_message = "nixos.runtime_dir must be a canonical absolute path other than /."
  }
}

data "coder_workspace" "me" {}

locals {
  flake_url    = try(replace(replace(var.nixos.flake_ref, "/^git\\+/", ""), "/\\?.*$/", ""), "")
  flake_branch = try(regex("[?&]ref=([^&#]+)", var.nixos.flake_ref)[0], "")
  nixos_count  = var.nixos.enabled ? data.coder_workspace.me.start_count : 0
  start_agent  = "${var.nixos.runtime_dir}/start-agent.sh"
  state_dir    = "/var/lib/coder-nixos"

  rebuild_script = templatefile("${path.module}/scripts/nixos/rebuild.sh.tftpl", {
    ARG_FLAKE_URL    = local.flake_url
    ARG_FLAKE_BRANCH = local.flake_branch
    ARG_FLAKE_ATTR   = coalesce(var.nixos.flake_attr, "none")
    ARG_FLAKE_DIR    = var.nixos.flake_dir
    ARG_LOG_DIR      = var.nixos.log_dir
    ARG_NIX_CONF     = local.nix_conf.nixos
    REBUILD_SH       = file("${path.module}/scripts/nixos/rebuild.sh")
  })
}

resource "coder_agent" "builder" {
  count = local.nixos_count
  arch  = var.nixos.arch
  os    = "linux"
  auth  = "token"
  order = var.nixos.order
  # Only bash and curl stand between the boot hook and this agent.
  connection_timeout = 300

  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = false
    ssh_helper             = false
    port_forwarding_helper = false
  }

  metadata {
    key          = "nixos"
    display_name = "NixOS version"
    interval     = 60
    timeout      = 10
    script       = <<-EOT
      version=$(nixos-version 2>/dev/null || echo unknown)
      if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
        echo "$version"
      else
        echo "$version (restart to apply update)"
      fi
    EOT
  }
  metadata {
    key          = "rev"
    display_name = "Applied revision"
    interval     = 60
    timeout      = 5
    script       = "cut -c1-12 ${local.state_dir}/flake.rev 2>/dev/null || echo none"
  }
  metadata {
    key          = "build_log"
    display_name = "Build log"
    interval     = 60
    timeout      = 5
    script       = "readlink -e ${var.nixos.log_dir}/rebuild-latest.log || echo ${var.nixos.log_dir}"
  }
  # The dashboard sorts metadata by key; this one comes last.
  metadata {
    key          = "status"
    display_name = "Rebuild status"
    interval     = 10
    timeout      = 5
    script       = "cat ${local.state_dir}/rebuild.status 2>/dev/null || echo unknown"
  }
}

resource "coder_script" "nixos_rebuild" {
  count        = local.nixos_count
  agent_id     = coder_agent.builder[0].id
  display_name = "NixOS rebuild"
  icon         = var.icon
  run_on_start = true
  # Coder drops all later agent logs past 1 MiB, so the output stops at a
  # budget; the transcript keeps the full rebuild output. The script is an
  # argument, not stdin, because git or nix could read stdin.
  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    status="$${STATE_DIR:-${local.state_dir}}/rebuild.status"
    mkdir -p "$(dirname "$status")"
    echo running >"$status"
    rc=0
    bash -c "$(base64 -d <<< '${base64encode(local.rebuild_script)}')" 2>&1 |
      LC_ALL=C awk -v max=524288 '
        { n += length($0) + 1 }
        n <= max { print; fflush(); next }
        !cut { cut = 1; print "Log output exceeds 512 KiB; the rest is in ${var.nixos.log_dir}/rebuild-latest.log"; fflush() }
      ' || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "failed (exit $rc)" >"$status"
      echo "The rebuild failed; the main agent stays stopped. Fix the flake, then run 'systemctl restart coder-builder' from this agent or restart the workspace." >&2
      exit "$rc"
    fi
    if ! ${local.start_agent}; then
      echo "ok; main agent did not start" >"$status"
      exit 1
    fi
    echo ok >"$status"
  EOT
}

output "boot_script" {
  description = "Root script for a boot hook (EC2 user-data, cloud-init, ...) to run on every boot. It publishes the main agent handoff and starts the builder agent, which rebuilds NixOS and then starts the main agent. Empty when nixos is disabled or the workspace is stopping."
  sensitive   = true
  value = local.nixos_count == 0 ? "" : templatefile("${path.module}/scripts/nixos/boot.sh.tftpl", {
    ARG_ACCESS_URL    = data.coder_workspace.me.access_url
    ARG_AGENT_TOKEN   = var.nixos.agent_token
    ARG_BUILDER_TOKEN = coder_agent.builder[0].token
    ARG_RUNTIME_DIR   = var.nixos.runtime_dir
    ARG_LOG_DIR       = var.nixos.log_dir
    INIT_SCRIPT       = coder_agent.builder[0].init_script
    START_AGENT = templatefile("${path.module}/scripts/nixos/start-agent.sh.tftpl", {
      ARG_RUNTIME_DIR = var.nixos.runtime_dir
    })
  })
}

output "builder_agent_id" {
  description = "ID of the root builder agent; null when nixos is disabled or the workspace is stopping."
  value       = local.nixos_count == 0 ? null : coder_agent.builder[0].id
}

output "flake_uri" {
  description = "Flake reference built, normalized for display; null when nixos is disabled."
  value       = !var.nixos.enabled ? null : "${local.flake_url}${local.flake_branch == "" ? "" : "?ref=${local.flake_branch}"}#${var.nixos.flake_attr}"
}

output "log_dir" {
  description = "Rebuild transcript and builder agent log directory; null when nixos is disabled."
  value       = var.nixos.enabled ? var.nixos.log_dir : null
}
