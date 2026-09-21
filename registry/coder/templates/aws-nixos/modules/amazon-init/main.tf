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
  }
}

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
    Extra files to write before the boot script runs, keyed by absolute path.
    Content is carried base64-encoded, so any bytes are safe.
  EOT
  type = map(object({
    content = string
    mode    = optional(string, "0644")
  }))
  default = {}

  validation {
    condition     = alltrue([for path in keys(var.files) : startswith(path, "/")])
    error_message = "File paths must be absolute."
  }
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

variable "curl_resolve_command" {
  description = <<-EOT
    Shell command that prints a path to a `curl` binary, used only when the
    image has none. Logging is the only thing that needs it, and it is the one
    thing this module cannot work out for an image it does not know.
  EOT
  type        = string
  default     = ""
}

variable "log_source_id" {
  description = "UUID of the log source boot output is streamed to. Must be constant across builds; Coder treats a repeat POST of the same id as a no-op."
  type        = string
  default     = "6e1f4a2c-9b3d-4c8e-8a71-5f0d2b6c4e93"

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.log_source_id))
    error_message = "log_source_id must be a UUID."
  }
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

  # Written by the bootstrap script before the boot script runs. Content is
  # base64 so that a heredoc in the file cannot terminate the one writing it.
  files_sh = join("\n", [
    for path, file in var.files : <<-SH
      install -d -m 0755 "$(dirname ${path})"
      printf '%s' '${base64encode(file.content)}' | base64 -d >'${path}'
      chmod ${file.mode} '${path}'
    SH
  ])

  bootstrap = templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
    LOG_SH      = file("${path.module}/scripts/log.sh")
    FILES_SH    = local.files_sh
    BOOT_SCRIPT = var.boot_script

    ARG_ACCESS_URL      = data.coder_workspace.me.access_url
    ARG_AGENT_TOKEN     = var.agent_token
    ARG_INIT_SCRIPT_B64 = base64encode(var.agent_init_script)
    ARG_RUNTIME_DIR     = var.runtime_dir
    ARG_PATH            = var.path

    ARG_LOG_SOURCE_ID        = var.log_source_id
    ARG_LOG_DISPLAY_NAME_B64 = base64encode(var.log_display_name)
    ARG_LOG_ICON             = var.log_icon
    ARG_LOG_BUDGET           = var.log_budget_bytes
    ARG_CURL_RESOLVE_B64     = base64encode(var.curl_resolve_command)

    ARG_HOSTNAME       = local.hostname
    ARG_WORKSPACE_NAME = data.coder_workspace.me.name
    ARG_OWNER          = data.coder_workspace_owner.me.name
    # base64 because a full name may contain quotes and is interpolated into
    # both a shell string and a JSON document.
    ARG_OWNER_NAME_B64 = base64encode(coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name))
    ARG_OWNER_EMAIL    = data.coder_workspace_owner.me.email
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
}

output "user_data_bytes" {
  description = "Size of the rendered user-data, for the caller's 16 KiB precondition. Unwrapped so the number can be shown in an error message."
  value       = nonsensitive(length(local.user_data))
}

output "log_library" {
  description = "The shell logging library, for callers that want `coder_log` in their own `coder_script`s. On the instance it is also at `$${runtime_dir}/log.sh`."
  value       = file("${path.module}/scripts/log.sh")
}

output "log_source_id" {
  description = "Log source the boot output is streamed to."
  value       = var.log_source_id
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
