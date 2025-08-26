terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    linode = {
      source = "linode/linode"
    }
  }
}

provider "coder" {}

# Variable for Linode API token
variable "linode_token" {
  description = "Linode API token for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# Configure the Linode Provider
provider "linode" {
  token = var.linode_token != "" ? var.linode_token : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

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
    script       = "coder stat disk --path /home/${lower(data.coder_workspace_owner.me.name)}"
  }
}

locals {
  vm_name           = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  root_disk_label   = substr("${local.vm_name}-root", 0, 32)
  home_volume_label = substr("${local.vm_name}-home", 0, 32)
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "This is the region where your workspace will be created."
  icon         = "/emojis/1f30e.png"
  type         = "string"
  default      = "us-east"
  mutable      = false

  option {
    name  = "Newark, NJ (US East)"
    value = "us-east"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Washington, DC (US East)"
    value = "us-iad"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Fremont, CA (US West)"
    value = "us-west"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Los Angeles, CA (US West)"
    value = "us-lax"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Dallas, TX (US Central)"
    value = "us-central"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Chicago, IL (US Central)"
    value = "us-ord"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Atlanta, GA (US Southeast)"
    value = "us-southeast"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Miami, FL (US Southeast)"
    value = "us-mia"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Seattle, WA (US West)"
    value = "us-sea"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Toronto, CA"
    value = "ca-central"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "London, UK"
    value = "eu-west"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "London 2, UK"
    value = "gb-lon"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "Frankfurt, DE"
    value = "eu-central"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "Frankfurt 2, DE"
    value = "de-fra-2"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "Paris, FR"
    value = "fr-par"
    icon  = "/emojis/1f1eb-1f1f7.png"
  }
  option {
    name  = "Amsterdam, NL"
    value = "nl-ams"
    icon  = "/emojis/1f1f3-1f1f1.png"
  }
  option {
    name  = "Stockholm, SE"
    value = "se-sto"
    icon  = "/emojis/1f1f8-1f1ea.png"
  }
  option {
    name  = "Madrid, ES"
    value = "es-mad"
    icon  = "/emojis/1f1ea-1f1f8.png"
  }
  option {
    name  = "Milan, IT"
    value = "it-mil"
    icon  = "/emojis/1f1ee-1f1f9.png"
  }
  option {
    name  = "Singapore, SG"
    value = "ap-south"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "Singapore 2, SG"
    value = "sg-sin-2"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "Tokyo 2, JP"
    value = "ap-northeast"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Tokyo 3, JP"
    value = "jp-tyo-3"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Osaka, JP"
    value = "jp-osa"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Sydney, AU"
    value = "ap-southeast"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Melbourne, AU"
    value = "au-mel"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Mumbai, IN"
    value = "ap-west"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Mumbai 2, IN"
    value = "in-bom-2"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Chennai, IN"
    value = "in-maa"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Jakarta, ID"
    value = "id-cgk"
    icon  = "/emojis/1f1ee-1f1e9.png"
  }
  option {
    name  = "Sao Paulo, BR"
    value = "br-gru"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance Type"
  description  = "Which Linode instance type would you like to use?"
  default      = "g6-nanode-1"
  type         = "string"
  icon         = "/icon/memory.svg"
  mutable      = false

  option {
    name  = "Nanode 1GB (1 vCPU, 1 GB RAM)"
    value = "g6-nanode-1"
  }
  option {
    name  = "Linode 2GB (1 vCPU, 2 GB RAM)"
    value = "g6-standard-1"
  }
  option {
    name  = "Linode 4GB (2 vCPU, 4 GB RAM)"
    value = "g6-standard-2"
  }
  option {
    name  = "Linode 8GB (4 vCPU, 8 GB RAM)"
    value = "g6-standard-4"
  }
  option {
    name  = "Linode 16GB (6 vCPU, 16 GB RAM)"
    value = "g6-standard-6"
  }
  option {
    name  = "Linode 32GB (8 vCPU, 32 GB RAM)"
    value = "g6-standard-8"
  }
}

data "coder_parameter" "instance_image" {
  name         = "instance_image"
  display_name = "Instance Image"
  description  = "Which Linode image would you like to use?"
  default      = "linode/ubuntu24.04"
  type         = "string"
  mutable      = false

  option {
    name  = "Ubuntu 24.04 LTS"
    value = "linode/ubuntu24.04"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Debian 13"
    value = "linode/debian13"
    icon  = "/icon/debian.svg"
  }
  option {
    name  = "Fedora 42"
    value = "linode/fedora42"
    icon  = "/icon/fedora.svg"
  }
  option {
    name  = "AlmaLinux 9"
    value = "linode/almalinux9"
    icon  = "/icon/almalinux.svg"
  }
  option {
    name  = "Rocky Linux 9"
    value = "linode/rocky9"
    icon  = "/icon/rockylinux.svg"
  }
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home Volume Size (GB)"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = 20
  mutable      = true

  validation {
    min       = 10
    max       = 1024
    monotonic = "increasing"
  }
}

resource "linode_volume" "home_volume" {
  label  = local.home_volume_label
  size   = data.coder_parameter.home_volume_size.value
  region = data.coder_parameter.region.value

  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
}

resource "linode_instance" "workspace" {
  count  = data.coder_workspace.me.start_count
  label  = local.vm_name
  region = data.coder_parameter.region.value
  type   = data.coder_parameter.instance_type.value

  private_ip = true

  metadata {
    user_data = base64encode(templatefile("cloud-init/cloud-config.yaml.tftpl", {
      hostname          = local.vm_name
      username          = lower(data.coder_workspace_owner.me.name)
      home_volume_label = linode_volume.home_volume.label
      init_script       = base64encode(coder_agent.main.init_script)
      coder_agent_token = coder_agent.main.token
    }))
  }
  tags = ["coder", "workspace", lower(data.coder_workspace_owner.me.name), lower(data.coder_workspace.me.name)]
}

# Create root disk
resource "linode_instance_disk" "root" {
  count     = data.coder_workspace.me.start_count
  label     = "boot"
  linode_id = linode_instance.workspace[0].id
  size      = 25000 # 25GB boot disk
  image     = data.coder_parameter.instance_image.value
}

# Create instance configuration with volume attached
resource "linode_instance_config" "workspace" {
  count     = data.coder_workspace.me.start_count
  label     = "${local.vm_name}-config"
  linode_id = linode_instance.workspace[0].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.root[0].id
  }

  device {
    device_name = "sdb"
    volume_id   = linode_volume.home_volume.id
  }

  root_device = "/dev/sda"
  kernel      = "linode/latest-64bit"
  booted      = true
}

resource "coder_metadata" "workspace-info" {
  count       = data.coder_workspace.me.start_count
  resource_id = linode_instance.workspace[0].id

  item {
    key   = "region"
    value = linode_instance.workspace[0].region
  }
  item {
    key   = "type"
    value = linode_instance.workspace[0].type
  }
}
