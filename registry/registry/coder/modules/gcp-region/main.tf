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
  default     = "GCP Region"
  description = "The display name of the parameter."
  type        = string
}

variable "description" {
  default     = "The region to deploy workspace infrastructure."
  description = "The description of the parameter."
  type        = string
}

variable "default" {
  default     = null
  description = "Default zone"
  type        = string
}

variable "regions" {
  description = "List of GCP regions to include."
  type        = list(string)
  default     = ["us-central1"]
}

variable "gpu_only" {
  description = "Whether to only include zones with GPUs."
  type        = bool
  default     = false
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

variable "single_zone_per_region" {
  default     = true
  description = "Whether to only include a single zone per region."
  type        = bool
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

locals {
  zones = {
    # US Central
    "us-central1-a" = {
      gpu  = true
      name = "Council Bluffs, Iowa, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-central1-b" = {
      gpu  = true
      name = "Council Bluffs, Iowa, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-central1-c" = {
      gpu  = true
      name = "Council Bluffs, Iowa, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-central1-f" = {
      gpu  = true
      name = "Council Bluffs, Iowa, USA (f)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    # US East
    "us-east1-b" = {
      gpu  = true
      name = "Moncks Corner, S. Carolina, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east1-c" = {
      gpu  = true
      name = "Moncks Corner, S. Carolina, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east1-d" = {
      gpu  = true
      name = "Moncks Corner, S. Carolina, USA (d)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    "us-east4-a" = {
      gpu  = true
      name = "Ashburn, Virginia, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east4-b" = {
      gpu  = true
      name = "Ashburn, Virginia, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east4-c" = {
      gpu  = true
      name = "Ashburn, Virginia, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    "us-east5-a" = {
      gpu  = false
      name = "Columbus, Ohio, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east5-b" = {
      gpu  = true
      name = "Columbus, Ohio, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east5-c" = {
      gpu  = false
      name = "Columbus, Ohio, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    # Us West
    "us-west1-a" = {
      gpu  = true
      name = "The Dalles, Oregon, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west1-b" = {
      gpu  = true
      name = "The Dalles, Oregon, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west1-c" = {
      gpu  = false
      name = "The Dalles, Oregon, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    "us-west2-a" = {
      gpu  = false
      name = "Los Angeles, California, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west2-b" = {
      gpu  = true
      name = "Los Angeles, California, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west2-c" = {
      gpu  = true
      name = "Los Angeles, California, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    "us-west3-a" = {
      gpu  = true
      name = "Salt Lake City, Utah, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west3-b" = {
      gpu  = true
      name = "Salt Lake City, Utah, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west3-c" = {
      gpu  = true
      name = "Salt Lake City, Utah, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    "us-west4-a" = {
      gpu  = true
      name = "Las Vegas, Nevada, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west4-b" = {
      gpu  = true
      name = "Las Vegas, Nevada, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west4-c" = {
      gpu  = true
      name = "Las Vegas, Nevada, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    # US South
    "us-south1-a" = {
      gpu  = false
      name = "Dallas, Texas, USA (a)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-south1-b" = {
      gpu  = false
      name = "Dallas, Texas, USA (b)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-south1-c" = {
      gpu  = false
      name = "Dallas, Texas, USA (c)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }

    # Canada
    "northamerica-northeast1-a" = {
      gpu  = true
      name = "Montréal, Québec, Canada (a)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "northamerica-northeast1-b" = {
      gpu  = true
      name = "Montréal, Québec, Canada (b)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "northamerica-northeast1-c" = {
      gpu  = true
      name = "Montréal, Québec, Canada (c)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }

    "northamerica-northeast2-a" = {
      gpu  = false
      name = "Toronto, Ontario, Canada (a)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "northamerica-northeast2-b" = {
      gpu  = false
      name = "Toronto, Ontario, Canada (b)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "northamerica-northeast2-c" = {
      gpu  = false
      name = "Toronto, Ontario, Canada (c)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }

    # South America East (Brazil, Chile)
    "southamerica-east1-a" = {
      gpu  = true
      name = "Osasco, São Paulo, Brazil (a)"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "southamerica-east1-b" = {
      gpu  = false
      name = "Osasco, São Paulo, Brazil (b)"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "southamerica-east1-c" = {
      gpu  = true
      name = "Osasco, São Paulo, Brazil (c)"
      icon = "/emojis/1f1e7-1f1f7.png"
    }

    "southamerica-west1-a" = {
      gpu  = false
      name = "Santiago, Chile (a)"
      icon = "/emojis/1f1e8-1f1f1.png"
    }
    "southamerica-west1-b" = {
      gpu  = false
      name = "Santiago, Chile (b)"
      icon = "/emojis/1f1e8-1f1f1.png"
    }
    "southamerica-west1-c" = {
      gpu  = false
      name = "Santiago, Chile (c)"
      icon = "/emojis/1f1e8-1f1f1.png"
    }

    # Europe North (Finland)
    "europe-north1-a" = {
      gpu  = false
      name = "Hamina, Finland (a)"
      icon = "/emojis/1f1e7-1f1ee.png"
    }
    "europe-north1-b" = {
      gpu  = false
      name = "Hamina, Finland (b)"
      icon = "/emojis/1f1e7-1f1ee.png"
    }
    "europe-north1-c" = {
      gpu  = false
      name = "Hamina, Finland (c)"
      icon = "/emojis/1f1e7-1f1ee.png"
    }

    # Europe Central (Poland)
    "europe-central2-a" = {
      gpu  = false
      name = "Warsaw, Poland (a)"
      icon = "/emojis/1f1f5-1f1f1.png"
    }
    "europe-central2-b" = {
      gpu  = true
      name = "Warsaw, Poland (b)"
      icon = "/emojis/1f1f5-1f1f1.png"
    }
    "europe-central2-c" = {
      gpu  = true
      name = "Warsaw, Poland (c)"
      icon = "/emojis/1f1f5-1f1f1.png"
    }

    # Europe Southwest (Spain)
    "europe-southwest1-a" = {
      gpu  = false
      name = "Madrid, Spain (a)"
      icon = "/emojis/1f1ea-1f1f8.png"
    }
    "europe-southwest1-b" = {
      gpu  = false
      name = "Madrid, Spain (b)"
      icon = "/emojis/1f1ea-1f1f8.png"
    }
    "europe-southwest1-c" = {
      gpu  = false
      name = "Madrid, Spain (c)"
      icon = "/emojis/1f1ea-1f1f8.png"
    }

    # Europe West
    "europe-west1-b" = {
      gpu  = true
      name = "St. Ghislain, Belgium (b)"
      icon = "/emojis/1f1e7-1f1ea.png"
    }
    "europe-west1-c" = {
      gpu  = true
      name = "St. Ghislain, Belgium (c)"
      icon = "/emojis/1f1e7-1f1ea.png"
    }
    "europe-west1-d" = {
      gpu  = true
      name = "St. Ghislain, Belgium (d)"
      icon = "/emojis/1f1e7-1f1ea.png"
    }

    "europe-west2-a" = {
      gpu  = true
      name = "London, England (a)"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "europe-west2-b" = {
      gpu  = true
      name = "London, England (b)"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "europe-west2-c" = {
      gpu  = false
      name = "London, England (c)"
      icon = "/emojis/1f1ec-1f1e7.png"
    }

    "europe-west3-b" = {
      gpu  = false
      name = "Frankfurt, Germany (b)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "europe-west3-c" = {
      gpu  = true
      name = "Frankfurt, Germany (c)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "europe-west3-d" = {
      gpu  = false
      name = "Frankfurt, Germany (d)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }

    "europe-west4-a" = {
      gpu  = true
      name = "Eemshaven, Netherlands (a)"
      icon = "/emojis/1f1f3-1f1f1.png"
    }
    "europe-west4-b" = {
      gpu  = true
      name = "Eemshaven, Netherlands (b)"
      icon = "/emojis/1f1f3-1f1f1.png"
    }
    "europe-west4-c" = {
      gpu  = true
      name = "Eemshaven, Netherlands (c)"
      icon = "/emojis/1f1f3-1f1f1.png"
    }

    "europe-west6-a" = {
      gpu  = false
      name = "Zurich, Switzerland (a)"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "europe-west6-b" = {
      gpu  = false
      name = "Zurich, Switzerland (b)"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "europe-west6-c" = {
      gpu  = false
      name = "Zurich, Switzerland (c)"
      icon = "/emojis/1f1e8-1f1ed.png"
    }

    "europe-west8-a" = {
      gpu  = false
      name = "Milan, Italy (a)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }
    "europe-west8-b" = {
      gpu  = false
      name = "Milan, Italy (b)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }
    "europe-west8-c" = {
      gpu  = false
      name = "Milan, Italy (c)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }

    "europe-west9-a" = {
      gpu  = false
      name = "Paris, France (a)"
      icon = "/emojis/1f1eb-1f1f7.png"
    }
    "europe-west9-b" = {
      gpu  = false
      name = "Paris, France (b)"
      icon = "/emojis/1f1eb-1f1f7.png"
    }
    "europe-west9-c" = {
      gpu  = false
      name = "Paris, France (c)"
      icon = "/emojis/1f1eb-1f1f7.png"
    }

    "europe-west10-a" = {
      gpu  = false
      name = "Berlin, Germany (a)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "europe-west10-b" = {
      gpu  = false
      name = "Berlin, Germany (b)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "europe-west10-c" = {
      gpu  = false
      name = "Berlin, Germany (c)"
      icon = "/emojis/1f1e9-1f1ea.png"
    }

    "europe-west12-a" = {
      gpu  = false
      name = "Turin, Italy (a)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }
    "europe-west12-b" = {
      gpu  = false
      name = "Turin, Italy (b)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }
    "europe-west12-c" = {
      gpu  = false
      name = "Turin, Italy (c)"
      icon = "/emojis/1f1ee-1f1f9.png"
    }

    # Middleeast Central (Qatar, Saudi Arabia)
    "me-central1-a" = {
      gpu  = false
      name = "Doha, Qatar (a)"
      icon = "/emojis/1f1f6-1f1e6.png"
    }
    "me-central1-b" = {
      gpu  = false
      name = "Doha, Qatar (b)"
      icon = "/emojis/1f1f6-1f1e6.png"
    }
    "me-central1-c" = {
      gpu  = false
      name = "Doha, Qatar (c)"
      icon = "/emojis/1f1f6-1f1e6.png"
    }

    "me-central2-a" = {
      gpu  = false
      name = "Dammam, Saudi Arabia (a)"
      icon = "/emojis/1f1f8-1f1e6.png"
    }
    "me-central2-b" = {
      gpu  = false
      name = "Dammam, Saudi Arabia (b)"
      icon = "/emojis/1f1f8-1f1e6.png"
    }
    "me-central2-c" = {
      gpu  = false
      name = "Dammam, Saudi Arabia (c)"
      icon = "/emojis/1f1f8-1f1e6.png"
    }

    # Middleeast West (Israel)
    "me-west1-a" = {
      gpu  = false
      name = "Tel Aviv, Israel (a)"
      icon = "/emojis/1f1ee-1f1f1.png"
    }
    "me-west1-b" = {
      gpu  = true
      name = "Tel Aviv, Israel (b)"
      icon = "/emojis/1f1ee-1f1f1.png"
    }
    "me-west1-c" = {
      gpu  = true
      name = "Tel Aviv, Israel (c)"
      icon = "/emojis/1f1ee-1f1f1.png"
    }

    # Asia East (Taiwan, Hong Kong)
    "asia-east1-a" = {
      gpu  = true
      name = "Changhua County, Taiwan (a)"
      icon = "/emojis/1f1f9-1f1fc.png"
    }
    "asia-east1-b" = {
      gpu  = true
      name = "Changhua County, Taiwan (b)"
      icon = "/emojis/1f1f9-1f1fc.png"
    }
    "asia-east1-c" = {
      gpu  = true
      name = "Changhua County, Taiwan (c)"
      icon = "/emojis/1f1f9-1f1fc.png"
    }

    "asia-east2-a" = {
      gpu  = true
      name = "Hong Kong (a)"
      icon = "/emojis/1f1ed-1f1f0.png"
    }
    "asia-east2-b" = {
      gpu  = false
      name = "Hong Kong (b)"
      icon = "/emojis/1f1ed-1f1f0.png"
    }
    "asia-east2-c" = {
      gpu  = true
      name = "Hong Kong (c)"
      icon = "/emojis/1f1ed-1f1f0.png"
    }

    # Asia Northeast (Japan, South Korea)
    "asia-northeast1-a" = {
      gpu  = true
      name = "Tokyo, Japan (a)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast1-b" = {
      gpu  = false
      name = "Tokyo, Japan (b)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast1-c" = {
      gpu  = true
      name = "Tokyo, Japan (c)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast2-a" = {
      gpu  = false
      name = "Osaka, Japan (a)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast2-b" = {
      gpu  = false
      name = "Osaka, Japan (b)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast2-c" = {
      gpu  = false
      name = "Osaka, Japan (c)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "asia-northeast3-a" = {
      gpu  = true
      name = "Seoul, South Korea (a)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "asia-northeast3-b" = {
      gpu  = true
      name = "Seoul, South Korea (b)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "asia-northeast3-c" = {
      gpu  = true
      name = "Seoul, South Korea (c)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }

    # Asia South (India)
    "asia-south1-a" = {
      gpu  = true
      name = "Mumbai, India (a)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "asia-south1-b" = {
      gpu  = true
      name = "Mumbai, India (b)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "asia-south1-c" = {
      gpu  = false
      name = "Mumbai, India (c)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "asia-south2-a" = {
      gpu  = false
      name = "Delhi, India (a)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "asia-south2-b" = {
      gpu  = false
      name = "Delhi, India (b)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "asia-south2-c" = {
      gpu  = false
      name = "Delhi, India (c)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }

    # Asia Southeast (Singapore, Indonesia)
    "asia-southeast1-a" = {
      gpu  = true
      name = "Jurong West, Singapore (a)"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "asia-southeast1-b" = {
      gpu  = true
      name = "Jurong West, Singapore (b)"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "asia-southeast1-c" = {
      gpu  = true
      name = "Jurong West, Singapore (c)"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "asia-southeast2-a" = {
      gpu  = true
      name = "Jakarta, Indonesia (a)"
      icon = "/emojis/1f1ee-1f1e9.png"
    }
    "asia-southeast2-b" = {
      gpu  = true
      name = "Jakarta, Indonesia (b)"
      icon = "/emojis/1f1ee-1f1e9.png"
    }
    "asia-southeast2-c" = {
      gpu  = true
      name = "Jakarta, Indonesia (c)"
      icon = "/emojis/1f1ee-1f1e9.png"
    }

    # Australia (Sydney, Melbourne)
    "australia-southeast1-a" = {
      gpu  = true
      name = "Sydney, Australia (a)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australia-southeast1-b" = {
      gpu  = true
      name = "Sydney, Australia (b)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australia-southeast1-c" = {
      gpu  = true
      name = "Sydney, Australia (c)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australia-southeast2-a" = {
      gpu  = false
      name = "Melbourne, Australia (a)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australia-southeast2-b" = {
      gpu  = false
      name = "Melbourne, Australia (b)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "australia-southeast2-c" = {
      gpu  = false
      name = "Melbourne, Australia (c)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
  }
}

data "coder_parameter" "region" {
  name         = "gcp_region"
  display_name = var.display_name
  description  = var.description
  icon         = "/icon/gcp.png"
  mutable      = var.mutable
  default      = var.default != null && var.default != "" && (!var.gpu_only || try(local.zones[var.default].gpu, false)) ? var.default : null
  order        = var.coder_parameter_order
  dynamic "option" {
    for_each = {
      for k, v in local.zones : k => v
      if anytrue([for d in var.regions : startswith(k, d)]) && (!var.gpu_only || v.gpu) && (!var.single_zone_per_region || endswith(k, "-a"))
    }
    content {
      icon = try(var.custom_icons[option.key], option.value.icon)
      # if single_zone_per_region is true, remove the zone letter from the name
      name        = try(var.custom_names[option.key], var.single_zone_per_region ? substr(option.value.name, 0, length(option.value.name) - 4) : option.value.name)
      description = option.key
      value       = option.key
    }
  }
}

output "value" {
  description = "GCP zone identifier."
  value       = data.coder_parameter.region.value
}

output "region" {
  description = "GCP region identifier."
  value       = substr(data.coder_parameter.region.value, 0, length(data.coder_parameter.region.value) - 2)
}
