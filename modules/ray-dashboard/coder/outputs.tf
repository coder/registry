output "ray_dashboard_url" {
  description = "The URL for accessing the Ray Dashboard"
  value       = coder_app.ray-dashboard.url
}

output "ray_dashboard_app_id" {
  description = "The ID of the Ray Dashboard app resource"
  value       = coder_app.ray-dashboard.id
}

output "ray_port" {
  description = "The port number used by Ray Dashboard"
  value       = var.port
}
