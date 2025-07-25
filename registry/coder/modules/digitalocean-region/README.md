---
display_name: DigitalOcean Region
description: Provides a region selection parameter for DigitalOcean resources
icon: ../../../../.icons/digitalocean.svg
maintainer_github: coder
verified: true
tags: [helper, digitalocean, region]
---

# DigitalOcean Region

This module provides a standardized region selection parameter for DigitalOcean resources. It includes all volume-supporting regions with user-friendly names and country flag icons.

## Features

- **Volume Support**: Only includes regions that support DigitalOcean volumes
- **User-Friendly**: Display names with country/city information
- **Visual Icons**: Country flag emojis for each region
- **Configurable**: Customizable default region and parameter details
- **Consistent**: Standardized region selection across templates

## Usage

### Basic Usage

```tf
module "region" {
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"
}

resource "digitalocean_volume" "home_volume" {
  region = module.region.value
  # ... other configuration
}

resource "digitalocean_droplet" "workspace" {
  region = module.region.value
  # ... other configuration
}
```

### Customized Configuration

```tf
module "region" {
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"

  default      = "sfo3"
  mutable      = true
  display_name = "Datacenter Location"
  description  = "Select the datacenter region for your development environment"
}

resource "digitalocean_droplet" "workspace" {
  region = module.region.value
  # ... other configuration
}
```

## Available Regions

The module includes the following DigitalOcean regions:

| Region Code | Location                       | Notes        |
| ----------- | ------------------------------ | ------------ |
| `tor1`      | Canada (Toronto)               | 🇨🇦           |
| `fra1`      | Germany (Frankfurt)            | 🇩🇪           |
| `blr1`      | India (Bangalore)              | 🇮🇳           |
| `ams3`      | Netherlands (Amsterdam)        | 🇳🇱 (Default) |
| `sgp1`      | Singapore                      | 🇸🇬           |
| `lon1`      | United Kingdom (London)        | 🇬🇧           |
| `sfo2`      | United States (California - 2) | 🇺🇸           |
| `sfo3`      | United States (California - 3) | 🇺🇸           |
| `nyc1`      | United States (New York - 1)   | 🇺🇸           |
| `nyc3`      | United States (New York - 3)   | 🇺🇸           |

> **Note**: Some regions (nyc1, sfo1, ams2) are excluded because they do not support volumes, which are commonly used for persistent data storage.

## Variables

| Variable       | Type     | Default                                                      | Description                                                |
| -------------- | -------- | ------------------------------------------------------------ | ---------------------------------------------------------- |
| `default`      | `string` | `"ams3"`                                                     | The default region to select                               |
| `mutable`      | `bool`   | `false`                                                      | Whether the region can be changed after workspace creation |
| `name`         | `string` | `"region"`                                                   | The name of the parameter                                  |
| `display_name` | `string` | `"Region"`                                                   | The display name of the parameter                          |
| `description`  | `string` | `"This is the region where your workspace will be created."` | The description of the parameter                           |
| `icon`         | `string` | `"/emojis/1f30e.png"`                                        | The icon to display for the parameter                      |

## Outputs

| Output         | Type     | Description                              |
| -------------- | -------- | ---------------------------------------- |
| `value`        | `string` | The selected region value (e.g., "ams3") |
| `name`         | `string` | The parameter name                       |
| `display_name` | `string` | The parameter display name               |

## Examples

### With Custom Default Region

```tf
module "region" {
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"

  default = "sfo3" # Default to San Francisco
}
```

### With Mutable Region Selection

```tf
module "region" {
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"

  mutable = true # Allow changing region after workspace creation
}
```

### Integration with DigitalOcean Resources

```tf
module "region" {
  source  = "registry.coder.com/coder/digitalocean-region/coder"
  version = "1.0.0"
}

resource "digitalocean_volume" "home_volume" {
  region                  = module.region.value
  name                    = "coder-${data.coder_workspace.me.id}-home"
  size                    = 20
  initial_filesystem_type = "ext4"
}

resource "digitalocean_droplet" "workspace" {
  region = module.region.value
  name   = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
  image  = "ubuntu-22-04-x64"
  size   = "s-2vcpu-4gb"

  volume_ids = [digitalocean_volume.home_volume.id]
}
```

## Benefits

1. **Standardization**: Consistent region selection across all DigitalOcean templates
2. **Maintenance**: Single place to update region options
3. **User Experience**: Better UX with descriptive names and icons
4. **Reliability**: Only includes regions that support required features
5. **Flexibility**: Customizable for different use cases
