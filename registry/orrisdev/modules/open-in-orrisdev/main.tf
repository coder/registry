terraform {
  required_version = ">= 1.7"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.20.0"
    }
  }
}

# Declarative registration only. This module creates the two Coder apps
# used by OrrisDev and installs nothing: no helper
# package, no workspace template, no provisioning, no dynamic discovery.
# Both apps bind to the caller-supplied Dev Container sub-agent.
resource "coder_app" "orrisdev_helper" {
  count        = var.start_count
  agent_id     = var.subagent_id
  slug         = var.helper_slug
  display_name = var.helper_display_name
  url          = var.helper_loopback_url
  subdomain    = true
  share        = "owner"
}

resource "coder_app" "open_in_orrisdev" {
  count        = var.start_count
  agent_id     = var.subagent_id
  slug         = var.open_slug
  display_name = var.open_display_name
  external     = true
  order        = var.open_order
  url = join("", [
    "orrisdev://coder/open?deployment=", urlencode(var.deployment_origin),
    "&workspace=", urlencode(var.workspace_id),
    "&config=", urlencode(var.config_path),
    "&folder=", urlencode(var.workspace_folder),
    "&app=", urlencode(var.helper_slug),
  ])

  lifecycle {
    precondition {
      condition     = var.open_slug != var.helper_slug
      error_message = "Helper and launcher must have distinct workspace app slugs."
    }
    precondition {
      condition     = length(join("", ["orrisdev://coder/open?deployment=", urlencode(var.deployment_origin), "&workspace=", urlencode(var.workspace_id), "&config=", urlencode(var.config_path), "&folder=", urlencode(var.workspace_folder), "&app=", urlencode(var.helper_slug)])) <= 16384
      error_message = "The encoded launcher URL exceeds OrrisDev's 16384-byte limit."
    }
  }
}
