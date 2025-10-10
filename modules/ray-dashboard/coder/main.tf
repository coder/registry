resource "coder_app" "ray-dashboard" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  icon         = var.icon
  url          = "http://localhost:${var.port}"
  subdomain    = var.subdomain
  share        = var.share

  healthcheck {
    url       = "http://localhost:${var.port}"
    interval  = var.healthcheck_interval
    threshold = var.healthcheck_threshold
  }
}
