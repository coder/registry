# --- Host cluster (where the workspace runs) ---
variable "host_cluster_name" {
  description = "EKS cluster name"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]*$", trimspace(var.host_cluster_name)))
    error_message = "Cluster name must match ^[0-9A-Za-z][0-9A-Za-z_-]*$ (no leading space)."
  }
}


# --- Admin: IaC tool & toggles ---
variable "iac_tool" {
  description = "Infrastructure as Code tool"
  type        = string
  default     = "terraform"
  validation {
    condition     = contains(["terraform", "cdk", "pulumi"], var.iac_tool)
    error_message = "Must be one of: terraform, cdk, pulumi"
  }
}


variable "enable_aws" {
  type    = bool
  default = true
}

variable "enable_azure" {
  type    = bool
  default = false
}

variable "enable_gcp" {
  type    = bool
  default = false
}

# --- AWS ---
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_role_arn" {
  type    = string
  default = "" # IRSA optional
}

variable "aws_access_key_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "aws_session_token" {
  description = "Optional STS session token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "repo_url" {
  description = "Git repository to clone into the workspace (optional)"
  type        = string
  default     = ""
}

variable "default_branch" {
  description = "Default branch name to use (if repo is empty or for initial checkout)"
  type        = string
  default     = "main"
}


# --- Azure ---
variable "azure_subscription_id" {
  type    = string
  default = ""
}

variable "azure_tenant_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "azure_client_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "azure_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

# --- GCP ---
variable "gcp_project_id" {
  type    = string
  default = ""
}

variable "gcp_service_account" {
  description = "Service Account JSON (paste full JSON) — leave empty if using WIF"
  type        = string
  default     = ""
  sensitive   = true
}


