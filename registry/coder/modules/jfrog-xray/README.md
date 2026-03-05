---
display_name: JFrog Xray
description: Fetch container image vulnerability scan results from JFrog Xray
icon: ../../../../.icons/jfrog-xray.svg
verified: true
tags: [jfrog, xray]
---

# JFrog Xray

This module fetches vulnerability scan results from JFrog Xray for container images stored in Artifactory. Use the outputs to display security information as workspace metadata.

```tf
module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url   = "https://example.jfrog.io/xray"
  xray_token = var.artifactory_access_token
  image      = "docker-local/myapp/backend:v1.0.0"
}

resource "coder_metadata" "xray_scan" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "/icon/shield.svg"

  item {
    key   = "Image"
    value = "docker-local/myapp/backend:v1.0.0"
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

## Prerequisites

1. Container images must be stored in JFrog Artifactory
2. JFrog Xray must be configured to scan your repositories
3. A valid JFrog access token with Xray read permissions

## Provider Configuration

The `xray` provider must be declared and configured in your template:

```tf
terraform {
  required_providers {
    xray = {
      source  = "jfrog/xray"
      version = ">= 2.0"
    }
  }
}

provider "xray" {
  url          = "https://example.jfrog.io/xray"
  access_token = var.artifactory_access_token
}
```

## Remote Repositories

When scanning images from remote (proxy) repositories, set `use_cache_repo = true`. This is because Artifactory stores cached images in a companion `-cache` repository where Xray indexes the scan results.

```tf
module "jfrog_xray" {
  source  = "registry.coder.com/coder/jfrog-xray/coder"
  version = "1.0.0"

  xray_url       = "https://example.jfrog.io/xray"
  xray_token     = var.artifactory_access_token
  image          = "docker-remote/library/nginx:latest"
  use_cache_repo = true
}
```
