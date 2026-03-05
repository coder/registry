---
display_name: JFrog Xray
description: Fetch container image vulnerability scan results from JFrog Xray
icon: ../../../../.icons/jfrog-xray.svg
verified: true
tags: [integration, jfrog, security]
---

# JFrog Xray

This module fetches vulnerability scan results from JFrog Xray for container images stored in Artifactory. It outputs vulnerability counts (Critical, High, Medium, Low) that you can display as workspace metadata.

```tf
provider "xray" {
  url                     = "${var.jfrog_url}/xray"
  access_token            = var.artifactory_access_token
  skip_xray_version_check = true
}

module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url   = "${var.jfrog_url}/xray"
  xray_token = var.artifactory_access_token
  image      = "docker-local/codercom/enterprise-base:latest"
}

resource "coder_metadata" "xray_vulnerabilities" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "/icon/shield.svg"

  item {
    key   = "Total Vulnerabilities"
    value = module.jfrog_xray.total
  }
  item {
    key   = "Critical"
    value = module.jfrog_xray.critical
  }
  item {
    key   = "High"
    value = module.jfrog_xray.high
  }
  item {
    key   = "Medium"
    value = module.jfrog_xray.medium
  }
  item {
    key   = "Low"
    value = module.jfrog_xray.low
  }
}
```

## Prerequisites

1. Container images must be stored in JFrog Artifactory
2. JFrog Xray must be configured to scan your repositories
3. A valid JFrog access token with Xray read permissions
4. Images must have been scanned by Xray (check **Xray → Scan List** in the JFrog UI)

## Important

The `xray` provider and `coder_metadata` resource must be defined in your root template, not inside the module. This is because:

- Terraform does not allow `count`, `for_each`, or `depends_on` on modules with inline provider configurations
- `coder_metadata` resources defined inside modules may not display correctly in the Coder dashboard

## Usage

### Basic Usage

Define the `xray` provider in your root template and use the module outputs to create metadata:

```hcl
provider "xray" {
  url                     = "${var.jfrog_url}/xray"
  access_token            = var.artifactory_access_token
  skip_xray_version_check = true
}

module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url   = "${var.jfrog_url}/xray"
  xray_token = var.artifactory_access_token
  image      = "docker-local/codercom/enterprise-base:latest"
}

resource "coder_metadata" "xray_vulnerabilities" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "/icon/shield.svg"

  item {
    key   = "Total Vulnerabilities"
    value = module.jfrog_xray.total
  }
  item {
    key   = "Critical"
    value = module.jfrog_xray.critical
  }
  item {
    key   = "High"
    value = module.jfrog_xray.high
  }
  item {
    key   = "Medium"
    value = module.jfrog_xray.medium
  }
  item {
    key   = "Low"
    value = module.jfrog_xray.low
  }
}
```

### With jfrog-token Module

Use alongside the `jfrog-token` module for a complete JFrog integration:

```hcl
variable "jfrog_url" {
  type        = string
  description = "JFrog instance URL (e.g. https://example.jfrog.io)"
}

variable "artifactory_access_token" {
  type        = string
  description = "Admin-level access token for JFrog."
  sensitive   = true
}

variable "docker_image" {
  type        = string
  description = "Container image in Artifactory (e.g. docker-remote/codercom/enterprise-base:ubuntu)"
  default     = "docker-remote/codercom/enterprise-base:ubuntu"
}

locals {
  jfrog_host = split("://", var.jfrog_url)[1]
}

provider "docker" {
  registry_auth {
    address  = "${var.jfrog_url}/artifactory/api/docker/${split("/", var.docker_image)[0]}"
    username = module.jfrog.username
    password = module.jfrog.access_token
  }
}

provider "xray" {
  url                     = "${var.jfrog_url}/xray"
  access_token            = var.artifactory_access_token
  skip_xray_version_check = true
}

module "jfrog" {
  source   = "registry.coder.com/coder/jfrog-token/coder"
  version  = "1.0.29"
  agent_id = coder_agent.main.id

  jfrog_url                = var.jfrog_url
  artifactory_access_token = var.artifactory_access_token
  check_license            = false

  package_managers = {
    docker = ["example.jfrog.io"]
  }
}

module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url   = "${var.jfrog_url}/xray"
  xray_token = var.artifactory_access_token
  image      = var.docker_image
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "${local.jfrog_host}/${var.docker_image}"
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # ...
}

resource "coder_metadata" "xray_vulnerabilities" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "/icon/shield.svg"

  item {
    key   = "Image"
    value = var.docker_image
  }
  item {
    key   = "Total Vulnerabilities"
    value = module.jfrog_xray.total
  }
  item {
    key   = "Critical"
    value = module.jfrog_xray.critical
  }
  item {
    key   = "High"
    value = module.jfrog_xray.high
  }
  item {
    key   = "Medium"
    value = module.jfrog_xray.medium
  }
  item {
    key   = "Low"
    value = module.jfrog_xray.low
  }
}
```

### Custom Repo and Path

If the image path doesn't follow the standard `repo/path:tag` format, specify repo and path separately:

```hcl
module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url  = "${var.jfrog_url}/xray"
  xray_token = var.artifactory_access_token
  image     = "docker-local/codercom/enterprise-base:latest"
  repo      = "docker-local"
  repo_path = "/codercom/enterprise-base:v2.1.0"
}
```

## Outputs

| Name | Description |
|------|-------------|
| `critical` | Number of critical vulnerabilities |
| `high` | Number of high vulnerabilities |
| `medium` | Number of medium vulnerabilities |
| `low` | Number of low vulnerabilities |
| `total` | Total number of vulnerabilities |

## Image Format Examples

```hcl
# Standard format
image = "docker-local/codercom/enterprise-base:latest"

# Nested paths
image = "docker-local/team/project/service:main-abc123"

# Remote repository (proxying Docker Hub)
image = "docker-remote/codercom/enterprise-base:ubuntu"
```
