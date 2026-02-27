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
  validation {
    condition     = can(regex("^(https|http)://", var.xray_url))
    error_message = "xray_url must be a valid URL starting with either 'https://' or 'http://'"
  }
}

variable "xray_token" {
  description = "The access token for JFrog Xray authentication."
  type        = string
  sensitive   = true
}

variable "image" {
  description = "The container image to scan in the format 'repo/path:tag' (e.g., 'docker-local/codercom/enterprise-base:latest')."
  type        = string
  validation {
    condition     = length(split("/", var.image)) >= 2
    error_message = "image must contain at least one '/' separating the repo from the path (e.g., 'docker-local/image:tag')."
  }
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

provider "xray" {
  url                    = var.xray_url
  access_token           = var.xray_token
  skip_xray_version_check = true
}

locals {
  image_parts = split("/", var.image)
  parsed_repo = var.repo != "" ? var.repo : local.image_parts[0]
  parsed_path = var.repo_path != "" ? var.repo_path : "/${join("/", slice(local.image_parts, 1, length(local.image_parts)))}"

  sec_issues = try(data.xray_artifacts_scan.image_scan.results[0].sec_issues, null)

  critical = try(local.sec_issues.critical, 0)
  high     = try(local.sec_issues.high, 0)
  medium   = try(local.sec_issues.medium, 0)
  low      = try(local.sec_issues.low, 0)
  total    = try(local.sec_issues.total, local.critical + local.high + local.medium + local.low)
}

data "xray_artifacts_scan" "image_scan" {
  repo      = local.parsed_repo
  repo_path = local.parsed_path
}

data "coder_workspace" "me" {}

resource "coder_metadata" "xray_vulnerabilities" {
  count       = data.coder_workspace.me.start_count
  resource_id = var.resource_id

  icon = "../../../../.icons/jfrog.svg"

  item {
    key   = "Image"
    value = var.image
  }

  item {
    key   = "Total Vulnerabilities"
    value = tostring(local.total)
  }

  item {
    key   = "Critical"
    value = tostring(local.critical)
  }

  item {
    key   = "High"
    value = tostring(local.high)
  }

  item {
    key   = "Medium"
    value = tostring(local.medium)
  }

  item {
    key   = "Low"
    value = tostring(local.low)
  }
}
