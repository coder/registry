terraform {
  required_version = ">= 1.0"
}

variable "server_url" {
  description = "URL of the Open Collaboration Tools server. HTTPS is required except for localhost development servers."
  type        = string

  validation {
    condition = (
      can(regex("^https://[^/[:space:]]+(:[0-9]{1,5})?(/[^[:space:]]*)?$", var.server_url)) ||
      can(regex("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?(/[^[:space:]]*)?$", var.server_url))
    )
    error_message = "server_url must use HTTPS, except that HTTP is allowed for localhost or 127.0.0.1."
  }
}

variable "extension_id" {
  description = "Identifier of the Open Collaboration Tools extension to configure."
  type        = string
  default     = "typefox.open-collaboration-tools"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]*\\.[A-Za-z0-9][A-Za-z0-9-]*$", var.extension_id))
    error_message = "extension_id must use the publisher.extension format."
  }
}

variable "extension_version" {
  description = "Version of the Open Collaboration Tools extension to install."
  type        = string
  default     = "0.3.9"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$", var.extension_version))
    error_message = "extension_version must be a semantic version such as 0.3.9."
  }
}

variable "install_extension" {
  description = "Whether compatible IDE modules should install the configured extension. Disable this when the extension is already present in the workspace image."
  type        = bool
  default     = true
}

variable "always_ask_to_override_server_url" {
  description = "Whether OCT should ask before switching to the server URL contained in an invitation."
  type        = bool
  default     = false
}

variable "join_accept_mode" {
  description = "Policy used by a host when another user requests to join: prompt, allowlist, or auto."
  type        = string
  default     = "prompt"

  validation {
    condition     = contains(["prompt", "allowlist", "auto"], var.join_accept_mode)
    error_message = "join_accept_mode must be prompt, allowlist, or auto."
  }
}

variable "join_allowlist" {
  description = "Usernames allowed to join without confirmation when join_accept_mode is allowlist."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for username in var.join_allowlist : trimspace(username) != ""])
    error_message = "join_allowlist entries must not be empty."
  }
}

variable "excluded_files" {
  description = "Glob patterns for files that OCT must not share with session participants."
  type        = list(string)
  default     = ["**/.env"]

  validation {
    condition     = alltrue([for pattern in var.excluded_files : trimspace(pattern) != ""])
    error_message = "excluded_files entries must not be empty."
  }
}

locals {
  normalized_server_url = "${trim(var.server_url, "/")}/"
  extension_spec        = "${var.extension_id}@${var.extension_version}"
}

output "extensions" {
  description = "Versioned extension identifiers to pass to a compatible web IDE module."
  value       = var.install_extension ? [local.extension_spec] : []
}

output "settings" {
  description = "Open Collaboration Tools settings to merge into a compatible IDE module."
  value = {
    "oct.serverUrl"                    = local.normalized_server_url
    "oct.alwaysAskToOverrideServerUrl" = var.always_ask_to_override_server_url
    "oct.joinAcceptMode"               = var.join_accept_mode
    "oct.joinAllowlist"                = var.join_allowlist
    "oct.files.exclude"                = var.excluded_files
  }
}
