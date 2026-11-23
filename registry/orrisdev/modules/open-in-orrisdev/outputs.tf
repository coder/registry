# Fixed route action and security defaults live in main.tf and are not
# inputs: helper is owner-private on subdomain routing; the launcher is an
# external app with no share attribute (coder provider 2.20.0 rejects
# share on external apps). Only these computed values are exposed.

output "helper_slug" {
  description = "Slug of the registered owner-private helper app."
  value       = var.helper_slug
}

output "open_slug" {
  description = "Slug of the registered external launcher app."
  value       = var.open_slug
}

output "launcher_url" {
  description = "The orrisdev://coder/open URL the launcher app registers. Carries deployment, workspace, config, folder, and helper slug only; no tokens or helper endpoint."
  value = join("", [
    "orrisdev://coder/open?deployment=", urlencode(var.deployment_origin),
    "&workspace=", urlencode(var.workspace_id),
    "&config=", urlencode(var.config_path),
    "&folder=", urlencode(var.workspace_folder),
    "&app=", urlencode(var.helper_slug),
  ])
}
