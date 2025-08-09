terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The resource ID of a Coder agent."
}

variable "agent_name" {
  type        = string
  description = "The name of a Coder agent. Needed for workspaces with multiple agents."
  default     = null
}

variable "folder" {
  type        = string
  description = "The directory to open in the IDE. e.g. /home/coder/project"
  validation {
    condition     = can(regex("^(?:/[^/]+)+/?$", var.folder))
    error_message = "The folder must be a full path and must not start with a ~."
  }
}

variable "default" {
  default     = []
  type        = set(string)
  description = <<-EOT
    The default IDE selection. Removes the selection from the UI. e.g. ["CL", "GO", "IU"]
  EOT
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "coder_app_order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

variable "major_version" {
  type        = string
  description = "The major version of the IDE. i.e. 2025.1"
  default     = "latest"
  validation {
    condition     = can(regex("^[0-9]{4}\\.[0-2]{1}$", var.major_version)) || var.major_version == "latest"
    error_message = "The major_version must be a valid version number. i.e. 2025.1 or latest"
  }
}

variable "channel" {
  type        = string
  description = "JetBrains IDE release channel. Valid values are release and eap."
  default     = "release"
  validation {
    condition     = can(regex("^(release|eap)$", var.channel))
    error_message = "The channel must be either release or eap."
  }
}

variable "options" {
  type        = set(string)
  description = "The list of IDE product codes."
  default     = ["CL", "GO", "IU", "PS", "PY", "RD", "RM", "RR", "WS"]
  validation {
    condition = (
      alltrue([
        for code in var.options : contains(["CL", "GO", "IU", "PS", "PY", "RD", "RM", "RR", "WS"], code)
      ])
    )
    error_message = "The options must be a set of valid product codes. Valid product codes are ${join(",", ["CL", "GO", "IU", "PS", "PY", "RD", "RM", "RR", "WS"])}."
  }
  # check if the set is empty
  validation {
    condition     = length(var.options) > 0
    error_message = "The options must not be empty."
  }
}

variable "releases_base_link" {
  type        = string
  description = "URL of the JetBrains releases base link."
  default     = "https://data.services.jetbrains.com"
  validation {
    condition     = can(regex("^https?://.+$", var.releases_base_link))
    error_message = "The releases_base_link must be a valid HTTP/S address."
  }
}

variable "download_base_link" {
  type        = string
  description = "URL of the JetBrains download base link."
  default     = "https://download.jetbrains.com"
  validation {
    condition     = can(regex("^https?://.+$", var.download_base_link))
    error_message = "The download_base_link must be a valid HTTP/S address."
  }
}

data "http" "jetbrains_ide_versions" {
  for_each = length(var.default) == 0 ? var.options : var.default
  url      = "${var.releases_base_link}/products/releases?code=${each.key}&type=${var.channel}&latest=true${var.major_version == "latest" ? "" : "&major_version=${var.major_version}"}"
}

variable "ide_config" {
  description = <<-EOT
    A map of JetBrains IDE configurations.
    The key is the product code and the value is an object with the following properties:
    - name: The name of the IDE.
    - icon: The icon of the IDE.
    - build: The build number of the IDE.
    Example:
    {
      "CL" = { name = "CLion", icon = "/icon/clion.svg", build = "251.26927.39" },
      "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "251.26927.50" },
      "IU" = { name = "IntelliJ IDEA", icon = "/icon/intellij.svg", build = "251.26927.53" },
    }
  EOT
  type = map(object({
    name  = string
    icon  = string
    build = string
  }))
  default = {
    "CL" = { name = "CLion", icon = "/icon/clion.svg", build = "251.26927.39" },
    "GO" = { name = "GoLand", icon = "/icon/goland.svg", build = "251.26927.50" },
    "IU" = { name = "IntelliJ IDEA", icon = "/icon/intellij.svg", build = "251.26927.53" },
    "PS" = { name = "PhpStorm", icon = "/icon/phpstorm.svg", build = "251.26927.60" },
    "PY" = { name = "PyCharm", icon = "/icon/pycharm.svg", build = "251.26927.74" },
    "RD" = { name = "Rider", icon = "/icon/rider.svg", build = "251.26927.67" },
    "RM" = { name = "RubyMine", icon = "/icon/rubymine.svg", build = "251.26927.47" },
    "RR" = { name = "RustRover", icon = "/icon/rustrover.svg", build = "251.26927.79" },
    "WS" = { name = "WebStorm", icon = "/icon/webstorm.svg", build = "251.26927.40" }
  }
  validation {
    condition     = length(var.ide_config) > 0
    error_message = "The ide_config must not be empty."
  }
  # ide_config must be a superset of var.. options
  validation {
    condition = alltrue([
      for code in var.options : contains(keys(var.ide_config), code)
    ])
    error_message = "The ide_config must be a superset of var.options."
  }
}

locals {
  # Parse HTTP responses once with error handling for air-gapped environments
  parsed_responses = {
    for code in length(var.default) == 0 ? var.options : var.default : code => try(
      jsondecode(data.http.jetbrains_ide_versions[code].response_body),
      {} # Return empty object if API call fails
    )
  }

  # Dynamically generate IDE configurations based on options with fallback to ide_config
  options_metadata = {
    for code in length(var.default) == 0 ? var.options : var.default : code => {
      icon       = var.ide_config[code].icon
      name       = var.ide_config[code].name
      identifier = code
      key        = code

      # Use API build number if available, otherwise fall back to ide_config build number
      build = length(keys(local.parsed_responses[code])) > 0 ? (
        local.parsed_responses[code][keys(local.parsed_responses[code])[0]][0].build
      ) : var.ide_config[code].build

      # Store API data for potential future use (only if API is available)
      json_data    = length(keys(local.parsed_responses[code])) > 0 ? local.parsed_responses[code][keys(local.parsed_responses[code])[0]][0] : null
      response_key = length(keys(local.parsed_responses[code])) > 0 ? keys(local.parsed_responses[code])[0] : null
    }
  }

  # Convert the parameter value to a set for for_each
  selected_ides = length(var.default) == 0 ? toset(jsondecode(coalesce(data.coder_parameter.jetbrains_ides[0].value, "[]"))) : toset(var.default)
}

data "coder_parameter" "jetbrains_ides" {
  count        = length(var.default) == 0 ? 1 : 0
  type         = "list(string)"
  name         = "jetbrains_ides"
  description  = "Select which JetBrains IDEs to configure for use in this workspace."
  display_name = "JetBrains IDEs"
  icon         = "/icon/jetbrains-toolbox.svg"
  mutable      = true
  default      = jsonencode([])
  order        = var.coder_parameter_order
  form_type    = "multi-select" # requires Coder version 2.24+

  dynamic "option" {
    for_each = var.options
    content {
      icon  = var.ide_config[option.value].icon
      name  = var.ide_config[option.value].name
      value = option.value
    }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "jetbrains" {
  for_each     = local.selected_ides
  agent_id     = var.agent_id
  slug         = "jetbrains-${lower(each.key)}"
  display_name = local.options_metadata[each.key].name
  icon         = local.options_metadata[each.key].icon
  external     = true
  order        = var.coder_app_order
  group        = var.group
  url = join("", [
    "jetbrains://gateway/coder?&workspace=", # requires 2.6.3+ version of Toolbox
    data.coder_workspace.me.name,
    "&owner=",
    data.coder_workspace_owner.me.name,
    "&folder=",
    var.folder,
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=",
    "$SESSION_TOKEN",
    "&ide_product_code=",
    each.key,
    "&ide_build_number=",
    local.options_metadata[each.key].build,
    var.agent_name != null ? "&agent_name=${var.agent_name}" : "",
  ])
}