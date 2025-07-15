---
display_name: GCP Region
description: Add Google Cloud Platform regions to your Coder template.
icon: ../../../../.icons/gcp.svg
verified: true
tags: [gcp, regions, parameter, helper]
---

# Google Cloud Platform Regions

This module adds Google Cloud Platform regions to your Coder template.

```tf
module "gcp_region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/gcp-region/coder"
  version = "1.0.31"
  regions = ["us", "europe"]
}

resource "google_compute_instance" "example" {
  zone = module.gcp_region.value
}
```

![GCP Regions](../../.images/gcp-regions.png)

## Examples

### Add only GPU zones in the US West 1 region

Note: setting `gpu_only = true` and using a default region without GPU support, the default will be set to `null`.

```tf
module "gcp_region" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/gcp-region/coder"
  version  = "1.0.31"
  default  = ["us-west1-a"]
  regions  = ["us-west1"]
  gpu_only = false
}

resource "google_compute_instance" "example" {
  zone = module.gcp_region.value
}
```

### Add all zones in the Europe West region

```tf
module "gcp_region" {
  count                  = data.coder_workspace.me.start_count
  source                 = "registry.coder.com/coder/gcp-region/coder"
  version                = "1.0.31"
  regions                = ["europe-west"]
  single_zone_per_region = false
}

resource "google_compute_instance" "example" {
  zone = module.gcp_region.value
}
```

### Add a single zone from each region in US and Europe that has GPUs

```tf
module "gcp_region" {
  count                  = data.coder_workspace.me.start_count
  source                 = "registry.coder.com/coder/gcp-region/coder"
  version                = "1.0.31"
  regions                = ["us", "europe"]
  gpu_only               = true
  single_zone_per_region = true
}

resource "google_compute_instance" "example" {
  zone = module.gcp_region.value
}
```
