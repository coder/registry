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

data "coder_workspace_owner" "me" {}

variable "boot_script" {
  description = "Root script to run on every boot, after the workspace facts and files are written. It inherits amazon-init's environment, including git, nix and nixos-rebuild on `PATH`. Sensitive, as it usually carries agent tokens."
  type        = string
  default     = ""
  sensitive   = true
}

variable "files" {
  description = <<-EOT
    Files to write before the boot script runs: absolute path to contents.
    Written mode 0644, parent directories created.

    Contents are carried gzipped and base64-encoded, so any text is safe --
    but note that user-data is itself compressed, and compressing twice buys
    nothing. This is for small files; the size precondition on `user_data` is
    what stops it being abused.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for path in keys(var.files) : startswith(path, "/")])
    error_message = "File paths must be absolute."
  }
}

variable "values" {
  description = <<-EOT
    Extra facts to publish in `workspace.json`, merged with the ones this
    module writes itself.

    This is the injection point for anything the machine needs to know at
    runtime: one map entry rather than a new file and a new variable each
    time. Keys this module writes (`workspace`, `owner`, `owner_name`,
    `owner_email`, `access_url`, `hostname`) win on conflict.

    Not for secrets. The file is world-readable, by design -- an unprivileged
    service reads it.
  EOT
  type        = map(string)
  default     = {}
}

variable "runtime_dir" {
  description = "Directory for the bootstrap, the boot script and the workspace facts. Must be on a tmpfs: the boot script usually holds tokens."
  type        = string
  default     = "/run/coder"

  validation {
    condition     = startswith(var.runtime_dir, "/") && var.runtime_dir != "/" && abspath(var.runtime_dir) == var.runtime_dir && !can(regex("[\\x00-\\x1f\\x7f]", var.runtime_dir))
    error_message = "runtime_dir must be a canonical absolute directory path without control characters."
  }
}

variable "path" {
  description = "Prepended to `PATH` for the boot script."
  type        = string
  default     = "/run/current-system/sw/bin"
}

variable "hostname" {
  description = "Hostname to set on the instance. Defaults to the workspace name."
  type        = string
  default     = ""
}

locals {
  hostname = var.hostname != "" ? var.hostname : lower(data.coder_workspace.me.name)

  files = [for path, content in var.files : {
    path    = base64encode(path)
    content = base64gzip(content)
  }]

  # Module-owned identity wins over caller-provided facts.
  facts = merge(var.values, {
    workspace   = data.coder_workspace.me.name
    owner       = data.coder_workspace_owner.me.name
    owner_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    owner_email = data.coder_workspace_owner.me.email
    access_url  = data.coder_workspace.me.access_url
    hostname    = local.hostname
  })

  bootstrap = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    FACTS_JSON  = jsonencode(local.facts)
    FILES       = local.files
    BOOT_SCRIPT = var.boot_script

    ARG_RUNTIME_DIR = base64encode(var.runtime_dir)
    ARG_PATH        = base64encode(var.path)
    ARG_HOSTNAME    = base64encode(local.hostname)
  })

  # EC2 caps user-data at 16 KiB; compress the bootstrap before sending it.
  user_data = <<-SH
    #!/usr/bin/env bash
    set -euo pipefail
    runtime_dir=$(printf %s '${base64encode(var.runtime_dir)}' | base64 -d)
    install -d -m 0700 -o root -g root -- "$runtime_dir"
    base64 -d <<'CODER_PAYLOAD' | gzip -dc | install -m 0700 -o root -g root /dev/stdin "$runtime_dir/bootstrap.sh"
    ${base64gzip(local.bootstrap)}
    CODER_PAYLOAD
    exec bash "$runtime_dir/bootstrap.sh"
  SH
}

output "user_data" {
  description = "Rendered EC2 user-data. Sensitive: it carries the boot script."
  value       = local.user_data
  sensitive   = true

  # Terraform suppresses error messages derived from sensitive values.
  precondition {
    condition     = nonsensitive(length(local.user_data)) < 16384
    error_message = "Rendered user-data is ${nonsensitive(length(local.user_data))} bytes; EC2 allows at most 16384."
  }
}

output "runtime_dir" {
  description = "Directory holding the bootstrap, the boot script and the workspace facts."
  value       = var.runtime_dir
}

output "workspace_facts_path" {
  description = "Path to the workspace identity file written on every boot."
  value       = "${var.runtime_dir}/workspace.json"
}

output "bootstrap_path" {
  description = "Where the user-data wrapper extracts the real boot script."
  value       = "${var.runtime_dir}/bootstrap.sh"
}
