terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.11"
    }
  }
}

variable "display_name" {
  default     = "Azure Region"
  description = "The display name of the Coder parameter."
  type        = string
}

variable "description" {
  default     = "The region where your workspace will live."
  description = "Description of the Coder parameter."
}

variable "default" {
  default     = ""
  description = "The default region to use if no region is specified."
  type        = string
}

variable "mutable" {
  default     = false
  description = "Whether the parameter can be changed after creation."
  type        = bool
}

variable "custom_names" {
  default     = {}
  description = "A map of custom display names for region IDs."
  type        = map(string)
}

variable "custom_icons" {
  default     = {}
  description = "A map of custom icons for region IDs."
  type        = map(string)
}

variable "exclude" {
  default     = []
  description = "A list of region IDs to exclude."
  type        = list(string)
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

locals {
  # Note: Options are limited to 64 regions, some redundant regions have been removed.
  all_regions = {
    "australia" = {
      name = "Australia"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australiacentral" = {
      name = "Australia Central"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australiacentral2" = {
      name = "Australia Central 2"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australiaeast" = {
      name = "Australia (New South Wales)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australiasoutheast" = {
      name = "Australia Southeast"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "brazil" = {
      name = "Brazil"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "brazilsouth" = {
      name = "Brazil (Sao Paulo)"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "brazilsoutheast" = {
      name = "Brazil Southeast"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "brazilus" = {
      name = "Brazil US"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "canada" = {
      name = "Canada"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "canadacentral" = {
      name = "Canada (Toronto)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "canadaeast" = {
      name = "Canada East"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "centralindia" = {
      name = "India (Pune)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "centralus" = {
      name = "US (Iowa)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "eastasia" = {
      name = "East Asia (Hong Kong)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "eastus" = {
      name = "US (Virginia)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "eastus2" = {
      name = "US (Virginia) 2"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "europe" = {
      name = "Europe"
      icon = "/emojis/1f30d.png"
    }
    "france" = {
      name = "France"
      icon = "/emojis/1f1eb-1f1f7.png"
    }
    "francecentral" = {
      name = "France (Paris)"
      icon = "/emojis/1f1eb-1f1f7.png"
    }
    "francesouth" = {
      name = "France South"
      icon = "/emojis/1f1eb-1f1f7.png"
    }
    "germany" = {
      name = "Germany"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "germanynorth" = {
      name = "Germany North"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "germanywestcentral" = {
      name = "Germany (Frankfurt)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "india" = {
      name = "India"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "japan" = {
      name = "Japan"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "japaneast" = {
      name = "Japan (Tokyo)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "japanwest" = {
      name = "Japan West"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "jioindiacentral" = {
      name = "Jio India Central"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "jioindiawest" = {
      name = "Jio India West"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "koreacentral" = {
      name = "Korea (Seoul)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "koreasouth" = {
      name = "Korea South"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "northcentralus" = {
      name = "North Central US"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "northeurope" = {
      name = "Europe (Ireland)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "norway" = {
      name = "Norway"
      icon = "/emojis/1f1f3-1f1f4.png"
    }
    "norwayeast" = {
      name = "Norway (Oslo)"
      icon = "/emojis/1f1f3-1f1f4.png"
    }
    "norwaywest" = {
      name = "Norway West"
      icon = "/emojis/1f1f3-1f1f4.png"
    }
    "qatarcentral" = {
      name = "Qatar (Doha)"
      icon = "/emojis/1f1f6-1f1e6.png"
    }
    "singapore" = {
      name = "Singapore"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "southafrica" = {
      name = "South Africa"
      icon = "/emojis/1f1ff-1f1e6.png"
    }
    "southafricanorth" = {
      name = "South Africa (Johannesburg)"
      icon = "/emojis/1f1ff-1f1e6.png"
    }
    "southafricawest" = {
      name = "South Africa West"
      icon = "/emojis/1f1ff-1f1e6.png"
    }
    "southcentralus" = {
      name = "US (Texas)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "southeastasia" = {
      name = "Southeast Asia (Singapore)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "southindia" = {
      name = "South India"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "swedencentral" = {
      name = "Sweden (Gävle)"
      icon = "/emojis/1f1f8-1f1ea.png"
    }
    "switzerland" = {
      name = "Switzerland"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "switzerlandnorth" = {
      name = "Switzerland (Zurich)"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "switzerlandwest" = {
      name = "Switzerland West"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "uae" = {
      name = "United Arab Emirates"
      icon = "/emojis/1f1e6-1f1ea.png"
    }
    "uaecentral" = {
      name = "UAE Central"
      icon = "/emojis/1f1e6-1f1ea.png"
    }
    "uaenorth" = {
      name = "UAE (Dubai)"
      icon = "/emojis/1f1e6-1f1ea.png"
    }
    "uk" = {
      name = "United Kingdom"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "uksouth" = {
      name = "UK (London)"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "ukwest" = {
      name = "UK West"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "unitedstates" = {
      name = "United States"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "westcentralus" = {
      name = "West Central US"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "westeurope" = {
      name = "Europe (Netherlands)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "westindia" = {
      name = "West India"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "westus" = {
      name = "West US"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "westus2" = {
      name = "US (Washington)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "westus3" = {
      name = "US (Arizona)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
  }
}

data "coder_parameter" "region" {
  name         = "azure_region"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  icon         = "/icon/azure.png"
  dynamic "option" {
    for_each = { for k, v in local.all_regions : k => v if !(contains(var.exclude, k)) }
    content {
      name  = try(var.custom_names[option.key], option.value.name)
      icon  = try(var.custom_icons[option.key], option.value.icon)
      value = option.key
    }
  }
}

output "value" {
  value = data.coder_parameter.region.value
}
