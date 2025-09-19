variable "agent_id" {
  description = "The ID of the Coder agent to install Ray on"
  type        = string
}

variable "slug" {
  description = "The slug for the Ray Dashboard app"
  type        = string
  default     = "ray-dashboard"
}

variable "display_name" {
  description = "The display name for the Ray Dashboard app"
  type        = string
  default     = "Ray Dashboard"
}

variable "icon" {
  description = "The icon URL for the Ray Dashboard app"
  type        = string
  default     = "https://raw.githubusercontent.com/ray-project/ray/master/doc/source/images/ray_logo.png"
}

variable "port" {
  description = "The port number for the Ray Dashboard"
  type        = number
  default     = 8265
}

variable "subdomain" {
  description = "Whether to use a subdomain for the Ray Dashboard"
  type        = bool
  default     = true
}

variable "share" {
  description = "The sharing level for the Ray Dashboard app"
  type        = string
  default     = "owner"
}

variable "healthcheck_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 5
}

variable "healthcheck_threshold" {
  description = "Health check threshold"
  type        = number
  default     = 10
}
