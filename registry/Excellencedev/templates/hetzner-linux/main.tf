terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    coder = {
      source = "coder/coder"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

variable "hcloud_token" {
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

data "http" "hcloud_locations" {
  url = "https://api.hetzner.cloud/v1/locations"

  request_headers = {
    Authorization = "Bearer ${var.hcloud_token}"
    Accept        = "application/json"
  }
}

data "http" "hcloud_server_types" {
  url = "https://api.hetzner.cloud/v1/server_types"

  request_headers = {
    Authorization = "Bearer ${var.hcloud_token}"
    Accept        = "application/json"
  }
}

# Available locations: https://docs.hetzner.com/cloud/general/locations/
data "coder_parameter" "hcloud_location" {
  name         = "hcloud_location"
  display_name = "Hetzner Location"
  description  = "Select the Hetzner Cloud location for your workspace."
  type         = "string"

  dynamic "option" {
    for_each = local.hcloud_locations
    content {
      name  = format(
        "%s (%s, %s)",
        upper(option.value.name),
        option.value.city,
        option.value.country
      )
      value = option.value.name
    }
  }
}

# Available server types: https://docs.hetzner.com/cloud/servers/overview/
data "coder_parameter" "hcloud_server_type" {
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

  # --------------------
  # Locations
  # --------------------
  hcloud_locations = [
    for loc in jsondecode(data.http.hcloud_locations.response_body).locations : {
      name        = loc.name
      city        = loc.city
      country     = loc.country
      description = loc.description
    }
  ]

  # --------------------
  # Server Types
  # --------------------
  hcloud_server_types = {
    for st in jsondecode(data.http.hcloud_server_types.response_body).server_types :
    st.name => {
      cores      = st.cores
      memory_gb  = st.memory
      disk_gb    = st.disk
      locations  = [for l in st.locations : l.name]
      deprecated = st.deprecated
    }
    if st.deprecated == false
  }

  hcloud_server_type_options_for_selected_location = [
    for name, meta in local.hcloud_server_types : {
      name = format(
        "%s (%d vCPU, %dGB RAM, %dGB)",
        upper(name),
        meta.cores,
        meta.memory_gb,
        meta.disk_gb
      )
      value = name
    }
    if contains(
      meta.locations,
      data.coder_parameter.hcloud_location.value
    )
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