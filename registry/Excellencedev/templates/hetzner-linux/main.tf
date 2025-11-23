terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    coder = {
      source = "coder/coder"
    }
  }
}

variable "hcloud_token" {
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

# Available locations: https://docs.hetzner.com/cloud/general/locations/
data "coder_parameter" "hcloud_location" {Expand commentComment on line R21ResolvedCode has comments. Press enter to view.
  name         = "hcloud_location"
  display_name = "Hetzner Location"
  description  = "Select the Hetzner Cloud location for your workspace."
  type         = "string"
  default      = "fsn1"
  option {
    name  = "DE Falkenstein"
    value = "fsn1"
  }
  option {
    name  = "US Ashburn, VA"
    value = "ash"
  }
  option {
    name  = "US Hillsboro, OR"
    value = "hil"
  }
  option {
    name  = "SG Singapore"
    value = "sin"
  }
  option {
    name  = "DE Nuremberg"
    value = "nbg1"
  }
  option {
    name  = "FI Helsinki"
    value = "hel1"
  }
}

# Available server types: https://docs.hetzner.com/cloud/servers/overview/
data "coder_parameter" "hcloud_server_type" {Expand commentComment on line R54ResolvedCode has comments. Press enter to view.
  name         = "hcloud_server_type"
  display_name = "Hetzner Server Type"
  description  = "Select the Hetzner Cloud server type for your workspace."
  type         = "string"

  dynamic "option" {
    for_each = local.hcloud_server_type_options_for_selected_location
    content {
      name  = option.value.name
      value = option.value.value
    }
  }
}

resource "hcloud_server" "dev" {
  count       = data.coder_workspace.me.start_count
  name        = "coder-${data.coder_workspace.me.name}-dev"
  image       = "ubuntu-24.04"
  server_type = data.coder_parameter.hcloud_server_type.value
  location    = data.coder_parameter.hcloud_location.value
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  user_data = templatefile("cloud-config.yaml.tftpl", {
    username          = lower(data.coder_workspace_owner.me.name)
    home_volume_label = "coder-${data.coder_workspace.me.id}-home"
    volume_id         = hcloud_volume.home_volume.id
    init_script       = base64encode(coder_agent.main.init_script)
    coder_agent_token = coder_agent.main.token
  })
  labels = {
    "coder_workspace_name"  = data.coder_workspace.me.name,
    "coder_workspace_owner" = data.coder_workspace_owner.me.name,
  }
}

resource "hcloud_volume" "home_volume" {
  name     = "coder-${data.coder_workspace.me.id}-home"
  size     = data.coder_parameter.home_volume_size.value
  location = data.coder_parameter.hcloud_location.value
  labels = {
    "coder_workspace_name"  = data.coder_workspace.me.name,
    "coder_workspace_owner" = data.coder_workspace_owner.me.name,
  }
}

resource "hcloud_volume_attachment" "home_volume_attachment" {
  count     = data.coder_workspace.me.start_count
  volume_id = hcloud_volume.home_volume.id
  server_id = hcloud_server.dev[count.index].id
  automount = false
}

locals {
  username = lower(data.coder_workspace_owner.me.name)

  # Data source: local JSON file under the module directory
  # Check API for latest server types & availability: https://docs.hetzner.cloud/reference/cloud#server-types
  hcloud_server_types_data        = jsondecode(file("${path.module}/hetzner_server_types.json"))
  hcloud_server_type_meta         = local.hcloud_server_types_data.type_meta
  hcloud_server_types_by_location = local.hcloud_server_types_data.availability

  hcloud_server_type_options_for_selected_location = [
    for type_name in lookup(local.hcloud_server_types_by_location, data.coder_parameter.hcloud_location.value, []) : {
      name  = format("%s (%d vCPU, %dGB RAM, %dGB)", upper(type_name), local.hcloud_server_type_meta[type_name].cores, local.hcloud_server_type_meta[type_name].memory_gb, local.hcloud_server_type_meta[type_name].disk_gb)
      value = type_name
    }
  ]
}

data "coder_provisioner" "me" {}

provider "coder" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home volume size"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = "20"
  mutable      = false
  validation {
    min = 1
    max = 100 # Adjust the max size as needed
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "home"
    display_name = "Home Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path /home/${local.username}"
  }
}

module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}