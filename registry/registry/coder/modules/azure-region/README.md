---
display_name: Azure Region
description: A parameter with human region names and icons
icon: ../../../../.icons/azure.svg
verified: true
tags: [helper, parameter, azure, regions]
---

# Azure Region

This module adds a parameter with all Azure regions, allowing developers to select the region closest to them.

```tf
module "azure_region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/azure-region/coder"
  version = "1.0.31"
  default = "eastus"
}

resource "azurem_resource_group" "example" {
  location = module.azure_region.value
}
```

![Azure Region Default](../../.images/azure-default.png)

## Examples

### Customize existing regions

Change the display name and icon for a region using the corresponding maps:

```tf
module "azure-region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/azure-region/coder"
  version = "1.0.31"
  custom_names = {
    "australia" : "Go Australia!"
  }
  custom_icons = {
    "australia" : "/icons/smiley.svg"
  }
}

resource "azurerm_resource_group" "example" {
  location = module.azure_region.value
}
```

![Azure Region Custom](../../.images/azure-custom.png)

### Exclude Regions

Hide all regions in Australia except australiacentral:

```tf
module "azure-region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/azure-region/coder"
  version = "1.0.31"
  exclude = [
    "australia",
    "australiacentral2",
    "australiaeast",
    "australiasoutheast"
  ]
}

resource "azurerm_resource_group" "example" {
  location = module.azure_region.value
}
```

![Azure Exclude](../../.images/azure-exclude.png)

## Related templates

For a complete Azure template, see the following examples in the [Coder Registry](https://registry.coder.com/).

- [Azure VM (Linux)](https://registry.coder.com/templates/azure-linux)
- [Azure VM (Windows)](https://registry.coder.com/templates/azure-windows)
