terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.23"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# --- Coder workspace context ---
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --- EKS connection ---
data "aws_eks_cluster" "eks" {
  name = trimspace(var.host_cluster_name)
}


data "aws_eks_cluster_auth" "eks" {
  name = trimspace(var.host_cluster_name)
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# --- Namespace per workspace ---
resource "kubernetes_namespace" "workspace" {
  metadata {
    name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    labels = {
      "coder.workspace" = data.coder_workspace.me.name
      "coder.owner"     = data.coder_workspace_owner.me.name
    }
  }
}

# --- ServiceAccount (IRSA optional) ---
resource "kubernetes_service_account" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    namespace = kubernetes_namespace.workspace.metadata[0].name

    annotations = var.enable_aws && var.aws_role_arn != "" ? {
      "eks.amazonaws.com/role-arn" = var.aws_role_arn
    } : {}
  }
}

# --- Coder Agent definition ---
resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  startup_script = file("${path.module}/scripts/setup-workspace.sh")

  env = {
    # IaC tool & cloud toggles
    IAC_TOOL     = var.iac_tool
    ENABLE_AWS   = tostring(var.enable_aws)
    ENABLE_AZURE = tostring(var.enable_azure)
    ENABLE_GCP   = tostring(var.enable_gcp)

    # Developer credentials
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    AZURE_CLIENT_ID       = var.azure_client_id
    AZURE_TENANT_ID       = var.azure_tenant_id
    AZURE_CLIENT_SECRET   = var.azure_client_secret
    GCP_SERVICE_ACCOUNT   = var.gcp_service_account
  }
}

# --- Kubernetes Pod (runs workspace container) ---
resource "kubernetes_pod" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    namespace = kubernetes_namespace.workspace.metadata[0].name
    labels = {
      "app"         = "coder-workspace"
      "coder.owner" = data.coder_workspace_owner.me.name
      "coder.agent" = "true"
    }
  }

  spec {
    service_account_name = kubernetes_service_account.workspace.metadata[0].name

    container {
      name    = "workspace"
      image   = "codercom/enterprise-base:ubuntu"
      command = ["/bin/bash", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = { cpu = "500m", memory = "1Gi" }
        limits   = { cpu = "2", memory = "4Gi" }
      }
    }
  }

  depends_on = [coder_agent.main]
}
