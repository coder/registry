---
display_name: DigitalOcean Region
description: A parameter with human region names and icons
icon: ../../../../.icons/digital-ocean.svg
verified: true
tags: [helper, parameter, digitalocean, regions]
---

# DigitalOcean Region

This module adds DigitalOcean regions to your Coder template with automatic GPU filtering. You can customize display names and icons using the `custom_names` and `custom_icons` arguments.

The simplest usage is:

```tf
module "digitalocean-region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"
  default = "ams3"
}
```

## Examples

### Basic usage

```tf
module "digitalocean-region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"
}
```

### With custom configuration

```tf
module "digitalocean-region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"
  default = "ams3"
  mutable = true

  custom_icons = {
    "ams3" = "/emojis/1f1f3-1f1f1.png"
  }

  custom_names = {
    "ams3" = "Europe - Amsterdam (Primary)"
  }
}
```

### GPU-only toggle (internal parameter)

This module automatically exposes a "GPU-only regions" checkbox in the template UI. When checked, it shows only GPU-capable regions and auto-selects the first one. When unchecked, it shows all available regions.

## Available Regions

Refer to DigitalOcean’s official availability matrix for the most up-to-date information.

- GPU availability: currently only in `nyc2` and `tor1` (per DO docs). Others are non-GPU.
- See: https://docs.digitalocean.com/platform/regional-availability/

### All datacenters (GPU status)

- `nyc2` - New York, United States (Legacy) - **GPU available**
- `tor1` - Toronto, Canada - **GPU available**
- `nyc3` - New York, United States
- `ams3` - Amsterdam, Netherlands
- `sfo3` - San Francisco, United States
- `sgp1` - Singapore
- `lon1` - London, United Kingdom
- `fra1` - Frankfurt, Germany
- `blr1` - Bangalore, India
- `syd1` - Sydney, Australia
- `atl1` - Atlanta, United States
- `nyc1` - New York, United States (Legacy)
- `sfo2` - San Francisco, United States (Legacy)
- `sfo1` - San Francisco, United States (Legacy)
- `ams2` - Amsterdam, Netherlands (Legacy)

## Associated template

Also see the Coder template registry for a [DigitalOcean Droplet template](https://registry.coder.com/templates/digitalocean-droplet) that provisions workspaces as DigitalOcean Droplets.
