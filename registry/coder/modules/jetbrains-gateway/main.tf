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

variable "arch" {
  type        = string
  description = "The target architecture of the workspace"
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "Architecture must be either 'amd64' or 'arm64'."
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "slug" {
  type        = string
  description = "The slug for the coder_app. Allows reusing the module with the same template."
  default     = "gateway"
}

variable "agent_name" {
  type        = string
  description = "Agent name."
  default     = ""
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
  default     = ""
  type        = string
  description = "Default IDE"
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

variable "latest" {
  type        = bool
  description = "Whether to fetch the latest version of the IDE."
  default     = false
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

variable "jetbrains_ide_versions" {
  type = map(object({
    build_number = string
    version      = string
  }))
  description = "The set of versions for each jetbrains IDE"
  default = {
    "IU" = {
      build_number = "243.21565.193"
      version      = "2024.3"
    }
    "PS" = {
      build_number = "243.21565.202"
      version      = "2024.3"
    }
    "WS" = {
      build_number = "243.21565.180"
      version      = "2024.3"
    }
    "PY" = {
      build_number = "243.21565.199"
      version      = "2024.3"
    }
    "CL" = {
      build_number = "243.21565.238"
      version      = "2024.1"
    }
    "GO" = {
      build_number = "243.21565.208"
      version      = "2024.3"
    }
    "RM" = {
      build_number = "243.21565.197"
      version      = "2024.3"
    }
    "RD" = {
      build_number = "243.21565.191"
      version      = "2024.3"
    }
    "RR" = {
      build_number = "243.22562.230"
      version      = "2024.3"
    }
  }
  validation {
    condition = (
      alltrue([
        for code in keys(var.jetbrains_ide_versions) : contains(["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"], code)
      ])
    )
    error_message = "The jetbrains_ide_versions must contain a map of valid product codes. Valid product codes are ${join(",", ["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"])}."
  }
}

variable "jetbrains_ides" {
  type        = list(string)
  description = "The list of IDE product codes."
  default     = ["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"]
  validation {
    condition = (
      alltrue([
        for code in var.jetbrains_ides : contains(["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"], code)
      ])
    )
    error_message = "The jetbrains_ides must be a list of valid product codes. Valid product codes are ${join(",", ["IU", "PS", "WS", "PY", "CL", "GO", "RM", "RD", "RR"])}."
  }
  # check if the list is empty
  validation {
    condition     = length(var.jetbrains_ides) > 0
    error_message = "The jetbrains_ides must not be empty."
  }
  # check if the list contains duplicates
  validation {
    condition     = length(var.jetbrains_ides) == length(toset(var.jetbrains_ides))
    error_message = "The jetbrains_ides must not contain duplicates."
  }
}

variable "releases_base_link" {
  type        = string
  description = ""
  default     = "https://data.services.jetbrains.com"
  validation {
    condition     = can(regex("^https?://.+$", var.releases_base_link))
    error_message = "The releases_base_link must be a valid HTTP/S address."
  }
}

variable "download_base_link" {
  type        = string
  description = ""
  default     = "https://download.jetbrains.com"
  validation {
    condition     = can(regex("^https?://.+$", var.download_base_link))
    error_message = "The download_base_link must be a valid HTTP/S address."
  }
}

variable "products_json_url" {
  type        = string
  description = <<-EOT
    URL of a products.json file generated by jetbrains-clients-downloader for an
    air-gapped mirror, e.g. https://mirror.example.com/backends/products.json.
    Use {code} as a placeholder for per-IDE files, e.g.
    https://mirror.example.com/backends/{code}/products.json. When set, the build
    number, version and download link are read from this file, relative download
    links are resolved against its directory, and `latest`,
    `jetbrains_ide_versions`, `releases_base_link` and `download_base_link` are ignored.
  EOT
  default     = null
  validation {
    condition     = var.products_json_url == null || can(regex("^https?://.+$", var.products_json_url))
    error_message = "The products_json_url must be a valid HTTP/S address."
  }
}

data "http" "jetbrains_ide_versions" {
  for_each = var.latest && var.products_json_url == null ? toset(var.jetbrains_ides) : toset([])
  url      = "${var.releases_base_link}/products/releases?code=${each.key}&latest=true&type=${var.channel}"
}

data "http" "products_json" {
  count = var.products_json_url != null ? 1 : 0
  url   = local.products_json_url
}

locals {
  # AMD64 versions of the images just use the version string, while ARM64
  # versions append "-aarch64". Eg:
  #
  # https://download.jetbrains.com/idea/ideaIU-2025.1.tar.gz
  # https://download.jetbrains.com/idea/ideaIU-2025.1.tar.gz
  #
  # We rewrite the data map above dynamically based on the user's architecture parameter.
  #
  effective_jetbrains_ide_versions = {
    for k, v in var.jetbrains_ide_versions : k => {
      build_number = v.build_number
      version      = var.arch == "arm64" ? "${v.version}-aarch64" : v.version
    }
  }

  # When downloading the latest IDE, the download link in the JSON is either:
  #
  # linux.download_link
  # linuxARM64.download_link
  #
  download_key = var.arch == "arm64" ? "linuxARM64" : "linux"

  jetbrains_ides = {
    "GO" = {
      icon          = "/icon/goland.svg",
      name          = "GoLand",
      identifier    = "GO",
      build_number  = local.effective_jetbrains_ide_versions["GO"].build_number,
      download_link = "${var.download_base_link}/go/goland-${local.effective_jetbrains_ide_versions["GO"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["GO"].version
    },
    "WS" = {
      icon          = "/icon/webstorm.svg",
      name          = "WebStorm",
      identifier    = "WS",
      build_number  = local.effective_jetbrains_ide_versions["WS"].build_number,
      download_link = "${var.download_base_link}/webstorm/WebStorm-${local.effective_jetbrains_ide_versions["WS"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["WS"].version
    },
    "IU" = {
      icon          = "/icon/intellij.svg",
      name          = "IntelliJ IDEA Ultimate",
      identifier    = "IU",
      build_number  = local.effective_jetbrains_ide_versions["IU"].build_number,
      download_link = "${var.download_base_link}/idea/ideaIU-${local.effective_jetbrains_ide_versions["IU"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["IU"].version
    },
    "PY" = {
      icon          = "/icon/pycharm.svg",
      name          = "PyCharm Professional",
      identifier    = "PY",
      build_number  = local.effective_jetbrains_ide_versions["PY"].build_number,
      download_link = "${var.download_base_link}/python/pycharm-professional-${local.effective_jetbrains_ide_versions["PY"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["PY"].version
    },
    "CL" = {
      icon          = "/icon/clion.svg",
      name          = "CLion",
      identifier    = "CL",
      build_number  = local.effective_jetbrains_ide_versions["CL"].build_number,
      download_link = "${var.download_base_link}/cpp/CLion-${local.effective_jetbrains_ide_versions["CL"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["CL"].version
    },
    "PS" = {
      icon          = "/icon/phpstorm.svg",
      name          = "PhpStorm",
      identifier    = "PS",
      build_number  = local.effective_jetbrains_ide_versions["PS"].build_number,
      download_link = "${var.download_base_link}/webide/PhpStorm-${local.effective_jetbrains_ide_versions["PS"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["PS"].version
    },
    "RM" = {
      icon          = "/icon/rubymine.svg",
      name          = "RubyMine",
      identifier    = "RM",
      build_number  = local.effective_jetbrains_ide_versions["RM"].build_number,
      download_link = "${var.download_base_link}/ruby/RubyMine-${local.effective_jetbrains_ide_versions["RM"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["RM"].version
    },
    "RD" = {
      icon          = "/icon/rider.svg",
      name          = "Rider",
      identifier    = "RD",
      build_number  = local.effective_jetbrains_ide_versions["RD"].build_number,
      download_link = "${var.download_base_link}/rider/JetBrains.Rider-${local.effective_jetbrains_ide_versions["RD"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["RD"].version
    },
    "RR" = {
      icon          = "/icon/rustrover.svg",
      name          = "RustRover",
      identifier    = "RR",
      build_number  = local.effective_jetbrains_ide_versions["RR"].build_number,
      download_link = "${var.download_base_link}/rustrover/RustRover-${local.effective_jetbrains_ide_versions["RR"].version}.tar.gz"
      version       = local.effective_jetbrains_ide_versions["RR"].version
    }
  }

  use_products_json = var.products_json_url != null
  use_api           = var.latest && !local.use_products_json

  products_json_url = local.use_products_json ? replace(var.products_json_url, "{code}", data.coder_parameter.jetbrains_ide.value) : null
  # Links in products.json are relative to the directory containing the file.
  products_json_dir = local.use_products_json ? replace(local.products_json_url, "/\\/[^/]*$/", "") : null

  # products.json is a list of products. Match on the product code or any of its
  # alternative codes, then take the newest release on the requested channel.
  mirror_products = local.use_products_json ? jsondecode(data.http.products_json[0].response_body) : []
  mirror_product = try(concat(
    [for p in local.mirror_products : p if try(p.code, "") == data.coder_parameter.jetbrains_ide.value],
    [for p in local.mirror_products : p if contains(try(p.alternativeCodes, []), data.coder_parameter.jetbrains_ide.value)],
  )[0], null)
  mirror_release = try([
    for r in local.mirror_product.releases : r
    if try(r.type, "release") == var.channel && can(r.downloads[local.download_key].link)
  ][0], null)
  mirror_link = try(local.mirror_release.downloads[local.download_key].link, "")

  icon          = local.jetbrains_ides[data.coder_parameter.jetbrains_ide.value].icon
  json_data     = local.use_api ? jsondecode(data.http.jetbrains_ide_versions[data.coder_parameter.jetbrains_ide.value].response_body) : {}
  key           = local.use_api ? keys(local.json_data)[0] : ""
  display_name  = local.jetbrains_ides[data.coder_parameter.jetbrains_ide.value].name
  identifier    = data.coder_parameter.jetbrains_ide.value
  download_link = local.use_products_json ? (can(regex("^https?://", local.mirror_link)) ? local.mirror_link : "${local.products_json_dir}/${trimprefix(local.mirror_link, "/")}") : local.use_api ? local.json_data[local.key][0].downloads[local.download_key].link : local.jetbrains_ides[data.coder_parameter.jetbrains_ide.value].download_link
  build_number  = local.use_products_json ? try(local.mirror_release.build, "") : local.use_api ? local.json_data[local.key][0].build : local.jetbrains_ides[data.coder_parameter.jetbrains_ide.value].build_number
  version       = local.use_products_json ? try(local.mirror_release.version, "") : local.use_api ? local.json_data[local.key][0].version : var.jetbrains_ide_versions[data.coder_parameter.jetbrains_ide.value].version
}

data "coder_parameter" "jetbrains_ide" {
  type         = "string"
  name         = "jetbrains_ide"
  display_name = "JetBrains IDE"
  icon         = "/icon/gateway.svg"
  mutable      = true
  default      = var.default == "" ? var.jetbrains_ides[0] : var.default
  order        = var.coder_parameter_order

  dynamic "option" {
    for_each = var.jetbrains_ides
    content {
      icon  = local.jetbrains_ides[option.value].icon
      name  = local.jetbrains_ides[option.value].name
      value = option.value
    }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "gateway" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = local.display_name
  icon         = local.icon
  external     = true
  order        = var.order
  group        = var.group

  lifecycle {
    precondition {
      condition     = !local.use_products_json || local.mirror_release != null
      error_message = "${data.coder_parameter.jetbrains_ide.value} has no ${var.channel} channel entry with a ${local.download_key} download in ${coalesce(local.products_json_url, "products.json")}."
    }
  }

  url = join("", [
    "jetbrains-gateway://connect#type=coder&workspace=",
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
    data.coder_parameter.jetbrains_ide.value,
    "&ide_build_number=",
    local.build_number,
    "&ide_download_link=",
    local.download_link,
    "&agent=",
    var.agent_name,
  ])
}

output "identifier" {
  value = local.identifier
}

output "display_name" {
  value = local.display_name
}

output "icon" {
  value = local.icon
}

output "download_link" {
  value = local.download_link
}

output "build_number" {
  value = local.build_number
}

output "version" {
  value = local.version
}

output "url" {
  value = coder_app.gateway.url
}
