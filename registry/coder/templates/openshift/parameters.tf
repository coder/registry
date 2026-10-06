variable "use_kubeconfig" {
  description = "Use ~/.kube/config on the provisioner instead of in-cluster authentication."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Existing OpenShift project in which to create workspaces."
  type        = string
  validation {
    condition     = length(var.namespace) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "The project must be a valid Kubernetes namespace name."
  }
}

variable "image" {
  description = "Workspace image supporting arbitrary UIDs, /home/user, and an entrypoint that executes the supplied command."
  type        = string
  default     = "quay.io/devfile/base-developer-image:ubi9-latest@sha256:51f3272c6944a13d7e8647fcfe4981e66b48a133f17980c3927786735822b12c"
  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "Provide an OpenShift-compatible workspace image."
  }
}

variable "arch" {
  description = "Workspace node architecture; the image must support this architecture."
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "The workspace architecture must be amd64 or arm64."
  }
}

variable "storage_class_name" {
  description = "StorageClass for persistent home volumes; leave empty to use the cluster default. It must support OpenShift-assigned fsGroup permissions."
  type        = string
  default     = ""
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "../../../../.icons/kubernetes.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "2"
  icon         = "../../../../.icons/kubernetes.svg"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "10"
  type         = "number"
  icon         = "../../../../.icons/folder.svg"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
}
