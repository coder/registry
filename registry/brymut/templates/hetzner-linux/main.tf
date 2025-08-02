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
data "coder_parameter" "hcloud_location" {
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
data "coder_parameter" "hcloud_server_type" {
  name         = "hcloud_server_type"
  display_name = "Hetzner Server Type"
  description  = "Select the Hetzner Cloud server type for your workspace."
  type         = "string"
  default      = "cx22"
  option {
    name  = "CX22 (2 vCPU, 4GB RAM, 40GB, $3.99/mo)"
    value = "cx22"
  }
  option {
    name  = "CPX11 (2 vCPU, 2GB RAM, 40GB, $4.49/mo)"
    value = "cpx11"
  }
  option {
    name  = "CX32 (4 vCPU, 8GB RAM, 80GB, $6.99/mo)"
    value = "cx32"
  }
  option {
    name  = "CPX21 (3 vCPU, 4GB RAM, 80GB, $7.99/mo)"
    value = "cpx21"
  }
  option {
    name  = "CPX31 (4 vCPU, 8GB RAM, 160GB, $14.99/mo)"
    value = "cpx31"
  }
  option {
    name  = "CX42 (8 vCPU, 16GB RAM, 160GB, $17.99/mo)"
    value = "cx42"
  }
  option {
    name  = "CPX41 (8 vCPU, 16GB RAM, 240GB, $27.49/mo)"
    value = "cpx41"
  }
  option {
    name  = "CX52 (16 vCPU, 32GB RAM, 320GB, $35.49/mo)"
    value = "cx52"
  }
  option {
    name  = "CPX51 (16 vCPU, 32GB RAM, 360GB, $60.49/mo)"
    value = "cpx51"
  }
}

resource "hcloud_server" "dev" {
  name        = "dev"
  image       = "ubuntu-24.04"
  server_type = data.coder_parameter.hcloud_server_type.value
  location    = data.coder_parameter.hcloud_location.value
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  user_data = templatefile("cloud-config.yaml.tftpl", {
    username          = lower(data.coder_workspace_owner.me.name)
    home_volume_label = hcloud_volume.home_volume.name
    init_script       = base64encode(coder_agent.main.init_script)
    coder_agent_token = coder_agent.main.token
  })
}

resource "hcloud_volume" "home_volume" {
  name              = "coder-${data.coder_workspace.me.id}-home"
  size              = data.coder_parameter.home_volume_size.value
  location          = data.coder_parameter.hcloud_location.value
  format            = "ext4"
  delete_protection = true
}

resource "hcloud_volume_attachment" "home_volume_attachment" {
  volume_id = hcloud_volume.home_volume.id
  server_id = hcloud_server.dev.id
}

locals {
  username = lower(data.coder_workspace_owner.me.name)
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
