# Cluster setup for the kubernetes-openshell template. A cluster
# administrator applies this once. See README.md in this directory.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
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

variable "gateway_namespace" {
  description = "The namespace for the OpenShell gateway. Terraform creates it."
  type        = string
  default     = "openshell"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_namespace)) && length(var.gateway_namespace) <= 63
    error_message = "gateway_namespace must be a valid Kubernetes namespace name."
  }
}

variable "gateway_name" {
  description = "The Helm release name of the gateway, and the name of its Service."
  type        = string
  default     = "openshell"
}

variable "openshell_version" {
  description = "The OpenShell Helm chart version. Use the same version for the CLI in build/launcher/Dockerfile."
  type        = string
  default     = "0.1.5"
}

variable "namespace" {
  description = "The namespace for workspaces and their OpenShell sandboxes. Terraform creates it. Use the same value in the template."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}

variable "runtimes" {
  description = "The Kata RuntimeClasses that the template offers: kata-qemu, kata-clh. Terraform labels them so that OpenShell admits them. Use the same value in the template."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.runtimes) == length(distinct(var.runtimes)) && alltrue([for r in var.runtimes : contains(["kata-qemu", "kata-clh"], r)])
    error_message = "runtimes can list only kata-qemu and kata-clh, each once."
  }
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

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context == "" ? null : var.kubeconfig_context
  }
}

resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = var.gateway_namespace
  }
}

resource "kubernetes_namespace_v1" "workspaces" {
  metadata {
    name = var.namespace
  }
}

# The gateway runs sandboxes as uid 1000, the coder user of the image, and
# accepts the driver config that mounts the Coder home disk.
resource "helm_release" "gateway" {
  name       = var.gateway_name
  namespace  = kubernetes_namespace_v1.gateway.metadata[0].name
  repository = "oci://ghcr.io/nvidia/openshell"
  chart      = "helm-chart"
  version    = var.openshell_version
  wait       = true

  values = [yamlencode({
    fullnameOverride = var.gateway_name
    server = {
      sandboxNamespace = kubernetes_namespace_v1.workspaces.metadata[0].name
      sandboxUid       = 1000
      telemetryEnabled = false
      drivers = {
        kubernetes = {
          allowDriverConfig = true
        }
      }
    }
  })]
}

# The gateway's certgen hook creates the client bundle in the gateway
# namespace.
data "kubernetes_secret_v1" "client_tls" {
  depends_on = [helm_release.gateway]
  metadata {
    name      = "openshell-client-tls"
    namespace = kubernetes_namespace_v1.gateway.metadata[0].name
  }
}

# Supervisor Pods mount ca.crt from this Secret and do not start without it.
# It holds no key.
resource "kubernetes_secret_v1" "sandbox_ca" {
  metadata {
    name      = "openshell-client-tls"
    namespace = kubernetes_namespace_v1.workspaces.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret_v1.client_tls.data["ca.crt"]
  }
}

# The launcher Pod of each workspace uses the client bundle to call the
# gateway. The template mounts it by this name.
resource "kubernetes_secret_v1" "launcher_tls" {
  metadata {
    name      = "openshell-launcher-tls"
    namespace = kubernetes_namespace_v1.workspaces.metadata[0].name
  }
  type = "kubernetes.io/tls"
  data = {
    "ca.crt"  = data.kubernetes_secret_v1.client_tls.data["ca.crt"]
    "tls.crt" = data.kubernetes_secret_v1.client_tls.data["tls.crt"]
    "tls.key" = data.kubernetes_secret_v1.client_tls.data["tls.key"]
  }
}

# OpenShell admits only RuntimeClasses with this label.
resource "kubernetes_labels" "runtime" {
  for_each    = toset(var.runtimes)
  api_version = "node.k8s.io/v1"
  kind        = "RuntimeClass"
  metadata {
    name = each.value
  }
  # Takes over the label if kubectl label set it before.
  force = true
  labels = {
    "openshell.ai/sandbox-attachable" = "true"
  }
}

# The provisioner manages launcher Pods, home disks, and agent token Secrets
# in the workspace namespace only.
resource "kubernetes_role_v1" "provisioner" {
  metadata {
    name      = "coder-kubernetes-openshell"
    namespace = kubernetes_namespace_v1.workspaces.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "persistentvolumeclaims", "secrets"]
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
    namespace = kubernetes_namespace_v1.workspaces.metadata[0].name
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

# A variables file for `coder templates push --variables-file`, so the
# template uses the same values. Coder reads every value as a string, and
# the template takes runtimes comma-separated.
output "coder_variables" {
  description = "The template variables for this setup, as YAML."
  value = yamlencode({
    namespace             = kubernetes_namespace_v1.workspaces.metadata[0].name
    openshell_gateway_url = "https://${var.gateway_name}.${var.gateway_namespace}.svc.cluster.local:8080"
    runtimes              = join(",", var.runtimes)
  })
}
