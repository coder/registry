terraform {
  required_version = ">= 1.0"

  required_providers {
    xray = {
      source  = "jfrog/xray"
      version = ">= 2.0"
    }
  }
}

provider "xray" {
  url          = var.xray_url
  access_token = var.xray_token
}

variable "xray_url" {
  description = "The URL of your JFrog Xray instance (e.g., https://mycompany.jfrog.io/xray). This should point to the Xray API endpoint, not Artifactory."
  type        = string
  validation {
    condition     = can(regex("^https?://", var.xray_url))
    error_message = "The xray_url must be a valid URL starting with http:// or https://."
  }
}

variable "xray_token" {
  description = "The access token for authenticating with JFrog Xray. This token needs read permissions on Xray scan results. You can generate one in JFrog Platform under User Management > Access Tokens."
  type        = string
  sensitive   = true
}

variable "image" {
  description = "The Docker image to check for vulnerabilities, in the format 'repo/path/image:tag'. For example: 'docker-local/myapp/backend:v1.0.0' or 'docker-remote/library/nginx:latest'. The repository name is extracted from the first path segment."
  type        = string
  validation {
    condition     = length(split("/", var.image)) >= 2
    error_message = "The image must include at least a repository and image name (e.g., 'docker-local/myimage:tag')."
  }
}

variable "repo" {
  description = "Override the repository name extracted from the image path. Use this when your Artifactory repository name differs from the first segment of your image path."
  type        = string
  default     = ""
}

variable "repo_path" {
  description = "Override the full Xray repository path. Use this for custom path structures that don't follow the standard 'repo/image:tag' format. When set, this takes precedence over automatic path construction."
  type        = string
  default     = ""
}

variable "use_cache_repo" {
  description = "Set to true when scanning images from remote (proxy) repositories. Remote repositories in Artifactory store cached artifacts in a companion '-cache' repository (e.g., 'docker-remote-cache'), which is where Xray indexes the scan results."
  type        = bool
  default     = false
}

locals {
  # Parse the image string into components
  # Example: "docker-local/myapp/backend:v1.0.0"
  #   -> repo: "docker-local", image_name: "myapp/backend", tag: "v1.0.0"
  image_parts = split("/", var.image)
  base_repo   = var.repo != "" ? var.repo : local.image_parts[0]
  parsed_repo = var.use_cache_repo ? "${local.base_repo}-cache" : local.base_repo
  image_path  = join("/", slice(local.image_parts, 1, length(local.image_parts)))
  image_name  = split(":", local.image_path)[0]
  image_tag   = length(split(":", local.image_path)) > 1 ? split(":", local.image_path)[1] : "latest"

  # Construct the Xray query path based on repository type:
  # - Local repositories: Query the exact tag path (e.g., /myapp/backend/v1.0.0)
  # - Remote repositories: Query by image name only (e.g., /myapp/backend) because
  #   the Terraform provider only returns the SHA manifest (with actual scan data)
  #   when querying the broader path
  parsed_path = var.repo_path != "" ? var.repo_path : (
    var.use_cache_repo ? "/${local.image_name}" : "/${local.image_name}/${local.image_tag}"
  )

  results = coalesce(try(data.xray_artifacts_scan.image_scan.results, []), [])

  # For remote repositories, filter to find the actual scanned image (not tag pointers):
  # - Tag manifests have size "0.00 B" (they're just pointers to SHA manifests)
  # - SHA manifests have actual size (e.g., "359.33 MB") and contain the real scan data
  # For local repositories, there's typically only one result which is the actual image
  scanned_images = var.use_cache_repo ? [
    for r in local.results : r if r.size != "0.00 B"
  ] : local.results

  # The artifact we'll report scan results for
  scan_result = (
    length(local.scanned_images) > 0 ? local.scanned_images[0] :
    length(local.results) > 0 ? local.results[0] :
    null
  )
}

data "xray_artifacts_scan" "image_scan" {
  repo      = local.parsed_repo
  repo_path = local.parsed_path
}

output "critical" {
  description = "The number of critical severity vulnerabilities found in the image. Critical vulnerabilities typically require immediate attention."
  value       = try(local.scan_result.sec_issues.critical, 0)
}

output "high" {
  description = "The number of high severity vulnerabilities found in the image."
  value       = try(local.scan_result.sec_issues.high, 0)
}

output "medium" {
  description = "The number of medium severity vulnerabilities found in the image."
  value       = try(local.scan_result.sec_issues.medium, 0)
}

output "low" {
  description = "The number of low severity vulnerabilities found in the image."
  value       = try(local.scan_result.sec_issues.low, 0)
}

output "total" {
  description = "The total number of vulnerabilities found across all severity levels."
  value       = try(local.scan_result.sec_issues.total, 0)
}

output "artifact_name" {
  description = "The name of the artifact that was scanned, as reported by Xray. For remote repositories, this will be the SHA-based manifest name (e.g., 'myimage/sha256__abc123...')."
  value       = try(local.scan_result.name, "")
}

output "violations" {
  description = "The number of Xray policy violations detected. Violations are triggered when vulnerabilities match rules defined in your Xray security policies."
  value       = try(local.scan_result.violations, 0)
}
