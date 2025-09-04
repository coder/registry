terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
    xray = {
      source  = "jfrog/xray"
      version = ">= 2.0"
    }
  }
}

variable "resource_id" {
  description = "The resource ID to attach the vulnerability metadata to."
  type        = string
}

variable "xray_url" {
  description = "The URL of the JFrog Xray instance (e.g., https://example.jfrog.io/xray)."
  type        = string
}

variable "xray_token" {
  description = "The access token for JFrog Xray authentication."
  type        = string
  sensitive   = true
}

variable "image" {
  description = "The container image to scan in the format 'repo/path:tag' (e.g., 'docker-local/codercom/enterprise-base:latest')."
  type        = string
}

variable "repo" {
  description = "The JFrog Artifactory repository name (e.g., 'docker-local'). If not provided, will be extracted from the image variable."
  type        = string
  default     = ""
}

variable "repo_path" {
  description = "The repository path including the image name and tag (e.g., '/codercom/enterprise-base:latest'). If not provided, will be extracted from the image variable."
  type        = string
  default     = ""
}

variable "display_name" {
  description = "The display name for the vulnerability metadata section."
  type        = string
  default     = "Security Vulnerabilities"
}

variable "icon" {
  description = "The icon to display for the vulnerability metadata."
  type        = string
  default     = "/icon/security.svg"
}

# Configure the Xray provider
provider "xray" {
  url           = var.xray_url
  access_token  = var.xray_token
  check_license = false
}

# Parse image components if repo and repo_path are not provided
locals {
  # Split image into repo and path components
  image_parts = split("/", var.image)

  # Extract repo (first part) and path (remaining parts)
  parsed_repo = var.repo != "" ? var.repo : local.image_parts[0]
  parsed_path = var.repo_path != "" ? var.repo_path : "/${join("/", slice(local.image_parts, 1, length(local.image_parts)))}"
}

# Get vulnerability scan results from Xray
data "xray_artifacts_scan" "image_scan" {
  repo      = local.parsed_repo
  repo_path = local.parsed_path
}

# Extract vulnerability counts
locals {
  vulnerabilities = length(data.xray_artifacts_scan.image_scan.results) > 0 ? data.xray_artifacts_scan.image_scan.results[0].sec_issues : {
    critical = 0
    high     = 0
    medium   = 0
    low      = 0
  }

  total_vulnerabilities = local.vulnerabilities.critical + local.vulnerabilities.high + local.vulnerabilities.medium + local.vulnerabilities.low
}

# Create metadata resource to display vulnerability information
resource "coder_metadata" "xray_vulnerabilities" {
  count       = data.coder_workspace.me.start_count
  resource_id = var.resource_id

  item {
    key   = "Image"
    value = var.image
  }

  item {
    key   = "Total Vulnerabilities"
    value = tostring(local.total_vulnerabilities)
  }

  item {
    key   = "Critical"
    value = tostring(local.vulnerabilities.critical)
  }

  item {
    key   = "High"
    value = tostring(local.vulnerabilities.high)
  }

  item {
    key   = "Medium"
    value = tostring(local.vulnerabilities.medium)
  }

  item {
    key   = "Low"
    value = tostring(local.vulnerabilities.low)
  }
}

# Data source for workspace information
data "coder_workspace" "me" {}
