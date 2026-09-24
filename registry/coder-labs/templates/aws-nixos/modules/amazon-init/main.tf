# Coder on an AMI that runs amazon-init instead of cloud-init.
#
# Renders EC2 user-data that publishes the agent handoff, publishes the
# workspace's identity, runs one boot script supplied by the caller, and then
# starts the agent. What that boot script does is none of this module's
# business: it is a string, and the module never looks inside it.

terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# The log source has to keep the same id for the life of the workspace --
# Coder treats a repeat POST of a known id as a no-op, and a value that
# changed every plan would churn user-data on every start. Terraform state is
# exactly the right place for that: stable across stop/start, new only when
# the workspace is recreated, by which point the agent and its logs are new
# too.
resource "random_uuid" "log_source" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "agent_token" {
  description = "Agent token. Written to `agent.env` at 0600 on a tmpfs."
  type        = string
  sensitive   = true
}

variable "agent_init_script" {
  description = "`coder_agent.init_script`, run verbatim once the boot script has finished."
  type        = string
  sensitive   = true
}

variable "boot_script" {
  description = <<-EOT
    Shell script run on every boot, after the handoff and workspace facts are
    published and before the agent is started.

    It runs as root, as a child process, with these set:

    | Variable                 | Meaning                                    |
    | ------------------------ | ------------------------------------------ |
    | `CODER_LOG_LIBRARY`      | path to source for `coder_log`             |
    | `CODER_RUNTIME_DIR`      | the tmpfs this module owns                 |
    | `CODER_WORKSPACE_FACTS`  | path to `workspace.json`                   |
    | `CODER_ACCESS_URL`       | deployment URL                             |
    | `CODER_AGENT_TOKEN`      | agent token                                |
    | `CODER_LOG_SOURCE_ID`    | log source to write to                     |

    Its exit status is reported and propagated, but never suppresses the agent
    start: a workspace whose boot script failed still has to be reachable.
  EOT
  type        = string
  default     = ""
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
    `owner_email`, `access_url`, `hostname`, `log_source_id`) win on conflict.

    Not for secrets. The file is world-readable, by design -- an unprivileged
    service reads it.
  EOT
  type        = map(string)
  default     = {}
}

variable "runtime_dir" {
  description = "Directory for the agent handoff and this module's own state. Must be on a tmpfs: it holds the token."
  type        = string
  default     = "/run/coder"
}

variable "path" {
  description = "Prepended to `PATH` for the boot script. amazon-init's own PATH is short."
  type        = string
  default     = "/run/current-system/sw/bin"
}

variable "log_display_name" {
  description = "Name of that log source in the workspace UI."
  type        = string
  default     = "Boot"
}

variable "log_icon" {
  description = "Icon for that log source."
  type        = string
  default     = "/icon/widgets.svg"
}

variable "log_budget_bytes" {
  description = <<-EOT
    How many bytes of log this module will push before going quiet.

    Coder caps agent logs at 1 MiB per agent across every source, and
    overflowing does not truncate: the agent is flagged overflowed and all
    later logs are dropped permanently. The default leaves half the cap for
    everything else.
  EOT
  type        = number
  default     = 524288
}

variable "hostname" {
  description = "Hostname to set on the instance. Defaults to the workspace name."
  type        = string
  default     = ""
}

locals {
  hostname = var.hostname != "" ? var.hostname : lower(data.coder_workspace.me.name)

  # Written by the bootstrap script before the boot script runs. Carried
  # gzipped and base64-encoded so that no content can terminate the heredoc
  # that writes it.
  files_sh = join("\n", [
    for path, content in var.files : <<-SH
      install -d -m 0755 "$(dirname '${path}')"
      printf '%s' '${base64gzip(content)}' | base64 -d | gzip -dc >'${path}'
      chmod 0644 '${path}'
    SH
  ])

  # Everything the machine is told about itself. Merged so that what this
  # module knows wins: a caller cannot accidentally rewrite the workspace's
  # own identity through `values`.
  facts = merge(var.values, {
    workspace   = data.coder_workspace.me.name
    owner       = data.coder_workspace_owner.me.name
    owner_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    owner_email = data.coder_workspace_owner.me.email
    access_url  = data.coder_workspace.me.access_url
    hostname    = local.hostname

    # The one thing a configuration on the instance cannot work out for
    # itself, and needs in order to log anywhere the user will see.
    log_source_id = random_uuid.log_source.result
  })

  bootstrap = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    FACTS_JSON = jsonencode(local.facts)

    LOG_SH      = file("${path.module}/scripts/log.sh")
    FILES_SH    = local.files_sh
    BOOT_SCRIPT = var.boot_script
    INIT_SCRIPT = var.agent_init_script

    ARG_ACCESS_URL  = data.coder_workspace.me.access_url
    ARG_AGENT_TOKEN = var.agent_token
    ARG_RUNTIME_DIR = var.runtime_dir
    ARG_PATH        = var.path

    ARG_LOG_SOURCE_ID        = random_uuid.log_source.result
    ARG_LOG_DISPLAY_NAME_B64 = base64encode(var.log_display_name)
    ARG_LOG_ICON             = var.log_icon
    ARG_LOG_BUDGET           = var.log_budget_bytes

    ARG_HOSTNAME = local.hostname
  })

  # EC2 caps user-data at 16 KiB and the script above plus its payloads is
  # comfortably past that, so user-data is a six-line self-extracting wrapper
  # around a compressed copy.
  #
  # This is transparent to amazon-init: it only inspects the first two bytes
  # for `#!` before exec'ing the blob, and it has no decompression step of its
  # own. Extracting to a fixed path also means the real script is on disk when
  # something needs debugging.
  user_data = <<-SH
    #!/usr/bin/env bash
    set -eu
    install -d -m 0700 ${var.runtime_dir}
    base64 -d <<'CODER_PAYLOAD' | gzip -dc >${var.runtime_dir}/bootstrap.sh
    ${base64gzip(local.bootstrap)}
    CODER_PAYLOAD
    exec bash ${var.runtime_dir}/bootstrap.sh
  SH
}

output "user_data" {
  description = "Rendered EC2 user-data. Sensitive: it carries the agent token."
  value       = local.user_data
  sensitive   = true

  # EC2 rejects user-data over 16 KiB, and it does so at apply time with an
  # error that says nothing about which part grew. Checking here fails the
  # plan instead, in the module that decides what goes in.
  #
  # nonsensitive because the length is sensitive by propagation, and Terraform
  # suppresses error messages derived from sensitive values.
  precondition {
    condition     = nonsensitive(length(local.user_data)) < 16384
    error_message = "Rendered user-data is ${nonsensitive(length(local.user_data))} bytes; EC2 allows at most 16384."
  }
}

output "log_source_id" {
  description = "Log source the boot output is streamed to."
  value       = random_uuid.log_source.result
}

output "runtime_dir" {
  description = "Directory holding the agent handoff, the logging library and the workspace facts."
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
