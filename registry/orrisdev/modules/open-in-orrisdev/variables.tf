# All inputs are finite and caller-supplied. There is no discovery, no
# provisioning, and no secret handling: tokens and the helper bearer stay
# out of Terraform state, URLs, and logs. Validation mirrors the app-side
# parser (ios/RoamCore/Sources/RoamCore/Coder.swift): exact HTTPS origin,
# UUID workspace, absolute config/folder paths without "." or ".."
# segments, and lowercase DNS-label slugs.

variable "subagent_id" {
  description = "Dev Container sub-agent both apps bind to (coder_devcontainer.<name>[*].subagent_id). Same value for helper and launcher; never the parent agent."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subagent_id))
    error_message = "subagent_id must be the selected Dev Container sub-agent UUID."
  }
}

variable "start_count" {
  description = "Pass data.coder_workspace.me.start_count so both apps exist only while the workspace runs."
  type        = number
  default     = 1

  validation {
    condition     = var.start_count == 0 || var.start_count == 1
    error_message = "start_count must be 0 or 1 (normally data.coder_workspace.me.start_count)."
  }
}

variable "deployment_origin" {
  description = "Deployment's externally reachable exact HTTPS origin, e.g. https://coder.example.com. No path, query, fragment, or credentials."
  type        = string

  validation {
    condition     = can(regex("^https://[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*(:[0-9]{1,5})?$", var.deployment_origin)) && length(var.deployment_origin) <= 2048 && try(tonumber(regex(":([0-9]+)$", var.deployment_origin)[0]) >= 1 && tonumber(regex(":([0-9]+)$", var.deployment_origin)[0]) <= 65535, true)
    error_message = "deployment_origin must be the exact HTTPS origin (scheme https, host only, no path/query/fragment/credentials/wildcard)."
  }
}

variable "workspace_id" {
  description = "Workspace UUID the launcher link opens."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.workspace_id))
    error_message = "workspace_id must be a UUID."
  }
}

variable "config_path" {
  description = "Exact Dev Container configuration path returned by Coder, e.g. /home/coder/repo/.devcontainer/devcontainer.json."
  type        = string

  validation {
    condition     = length(regexall("%[0-9A-Fa-f]{2}|[^%]", urlencode(var.config_path))) <= 4096 && can(regex("^/", var.config_path)) && !can(regex("[[:cntrl:]]|(^|/)(\\.|\\.\\.)($|/)", var.config_path))
    error_message = "config_path must be absolute, at most 4096 bytes, and contain no \".\" or \"..\" segments."
  }
}

variable "workspace_folder" {
  description = "Exact workspace folder returned by Coder, e.g. /home/coder/repo."
  type        = string

  validation {
    condition     = length(regexall("%[0-9A-Fa-f]{2}|[^%]", urlencode(var.workspace_folder))) <= 4096 && can(regex("^/", var.workspace_folder)) && !can(regex("[[:cntrl:]]|(^|/)(\\.|\\.\\.)($|/)", var.workspace_folder))
    error_message = "workspace_folder must be absolute, at most 4096 bytes, and contain no \".\" or \"..\" segments."
  }
}

variable "helper_slug" {
  description = "Slug of the owner-private helper app. Also embedded in the launcher URL, so it must satisfy the app-side DNS-label check."
  type        = string
  default     = "orrisdev"

  validation {
    condition     = length(var.helper_slug) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.helper_slug))
    error_message = "helper_slug must be a lowercase DNS label: up to 63 chars, letters/digits/hyphens, not starting or ending with a hyphen."
  }
}

variable "helper_display_name" {
  description = "Display name of the helper app in the Coder dashboard."
  type        = string
  default     = "OrrisDev helper"
}

variable "helper_loopback_url" {
  description = "Trusted helper's configured loopback HTTPS URL. Must stay a loopback address; the helper bearer and tokens are never part of it."
  type        = string
  default     = "https://localhost:8443"

  validation {
    condition     = can(regex("^https://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?/?$", var.helper_loopback_url)) && try(tonumber(regex(":([0-9]+)/?$", var.helper_loopback_url)[0]) >= 1 && tonumber(regex(":([0-9]+)/?$", var.helper_loopback_url)[0]) <= 65535, true)
    error_message = "helper_loopback_url must be an https:// loopback URL (localhost or 127.0.0.1, optional port, no path/query/fragment/credentials)."
  }
}

variable "open_slug" {
  description = "Slug of the external launcher app."
  type        = string
  default     = "open-in-orrisdev"

  validation {
    condition     = length(var.open_slug) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.open_slug))
    error_message = "open_slug must be a lowercase DNS label: up to 63 chars, letters/digits/hyphens, not starting or ending with a hyphen."
  }
}

variable "open_display_name" {
  description = "Display name of the launcher app in the Coder dashboard."
  type        = string
  default     = "Open in OrrisDev"
}

variable "open_order" {
  description = "Dashboard ordering of the launcher app."
  type        = number
  default     = 1
}
