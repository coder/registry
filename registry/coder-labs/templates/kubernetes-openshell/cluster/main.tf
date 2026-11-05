# Cluster setup for the kubernetes-openshell template. A cluster
# administrator applies this once. See README.md in this directory.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

variable "kubeconfig_path" {
  description = "The kubeconfig file to use."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "The kubeconfig context to use. Empty uses the current context."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "The namespace for workspaces. Use the same value in the template."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}

variable "create_namespace" {
  description = "Create the namespace. Set false if it exists already. Changing this from true to false deletes the namespace."
  type        = bool
  default     = true
}

variable "provisioner_service_account" {
  description = "The ServiceAccount of the Coder provisioner. The Coder Helm chart uses coder in the coder namespace."
  type = object({
    name      = string
    namespace = string
  })
  default = {
    name      = "coder"
    namespace = "coder"
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context == "" ? null : var.kubeconfig_context
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace_v1.workspaces[0].metadata[0].name : var.namespace
}

resource "kubernetes_namespace_v1" "workspaces" {
  count = var.create_namespace ? 1 : 0
  metadata {
    name = var.namespace
  }
}

# The provisioner manages workspaces in this namespace only.
resource "kubernetes_role_v1" "provisioner" {
  metadata {
    name      = "coder-kubernetes-openshell"
    namespace = local.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "persistentvolumeclaims", "secrets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  # Read-only, to debug workspaces with kubectl as the provisioner.
  rule {
    api_groups = [""]
    resources  = ["pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "provisioner" {
  metadata {
    name      = "coder-kubernetes-openshell"
    namespace = local.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.provisioner.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.provisioner_service_account.name
    namespace = var.provisioner_service_account.namespace
  }
}

output "namespace" {
  description = "The workspace namespace. Set it as the namespace template variable."
  value       = local.namespace
}
