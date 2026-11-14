terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.11"
    }
  }
}

variable "display_name" {
  default     = "Kubernetes cluster version"
  description = "The display name of the parameter."
  type        = string
}

variable "description" {
  default     = "The Kubernetes version to use for the workspace cluster."
  description = "The description of the parameter."
  type        = string
}

variable "default" {
  default     = null
  description = "Default Kubernetes version"
  type        = string
}

variable "mutable" {
  default     = false
  description = "Whether the parameter can be changed after creation."
  type        = bool
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation."
  default     = null
}

data "coder_parameter" "cluster_version" {
  name         = "kubernetes_cluster_version"
  display_name = var.display_name
  description  = var.description
  icon         = "/icon/kubernetes.svg"
  mutable      = var.mutable
  default      = var.default != null ? var.default : "1.31"
  order        = var.coder_parameter_order

  option {
    name  = "Stable (1.31)"
    value = "1.31"
    icon  = "/emojis/2705.png"
  }
  option {
    name  = "Previous (1.30)"
    value = "1.30"
    icon  = "/emojis/23eb.png"
  }
  option {
    name  = "Preview (1.32)"
    value = "1.32"
    icon  = "/emojis/1f5fa.png"
  }
}

output "value" {
  description = "Selected Kubernetes cluster version."
  value       = data.coder_parameter.cluster_version.value
}
