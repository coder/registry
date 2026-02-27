---
display_name: JFrog Xray
description: Display container image vulnerability scan results from JFrog Xray in workspace metadata
icon: ../../../../.icons/jfrog-xray.svg
verified: true
tags: [integration, jfrog, security]
---

# JFrog Xray

This module integrates JFrog Xray vulnerability scanning results into Coder workspace metadata. It displays vulnerability counts (Critical, High, Medium, Low) for container images directly on the workspace page.

```tf
module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  resource_id = docker_container.workspace.id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

## Prerequisites

1. Container images must be stored in JFrog Artifactory
2. JFrog Xray must be configured to scan your repositories
3. A valid JFrog access token with Xray read permissions
4. Images must have been scanned by Xray

## Usage

### Basic Usage

```hcl
module "jfrog_xray" {
  source      = "registry.coder.com/coder/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id = docker_container.workspace.id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

### Custom Repo and Path

```hcl
module "jfrog_xray" {
  source      = "registry.coder.com/coder/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id = docker_container.workspace.id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"

  # Specify repo and path separately for more control
  repo        = "docker-local"
  repo_path   = "/codercom/enterprise-base:v2.1.0"
}
```

### Complete Template Example

```hcl
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "jfrog_access_token" {
  description = "JFrog access token for Xray API"
  type        = string
  sensitive   = true
}

data "coder_workspace" "me" {}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "example.jfrog.io/docker-local/codercom/enterprise-base:latest"
  name  = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
}

module "jfrog_xray" {
  source      = "registry.coder.com/coder/jfrog-xray/coder"
  version     = "1.0.0"

  resource_id = docker_container.workspace[0].id
  xray_url    = "https://example.jfrog.io/xray"
  xray_token  = var.jfrog_access_token
  image       = "docker-local/codercom/enterprise-base:latest"
}
```

## Image Format Examples

```hcl
# Standard format
image = "docker-local/codercom/enterprise-base:latest"

# Nested paths
image = "docker-local/team/project/service:main-abc123"
```
