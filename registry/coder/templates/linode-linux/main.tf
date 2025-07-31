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

# Configure the Linode Provider
provider "linode" {
  # Recommended: use environment variable LINODE_TOKEN with your personal access token when starting coderd
  # alternatively, you can pass the token via a variable.
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

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains-gateway
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/jetbrains-gateway/coder"

  # JetBrains IDEs to make available for the user to select
  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "IU"

  # Default folder to open when starting a JetBrains IDE
  folder = "/home/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  order      = 2
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
    name  = "United States (East)"
    value = "us-east"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (West)"
    value = "us-west"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (Central)"
    value = "us-central"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (Southeast)"
    value = "us-southeast"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Canada (Central)"
    value = "ca-central"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "United Kingdom (London)"
    value = "eu-west"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "Germany (Frankfurt)"
    value = "eu-central"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "Singapore"
    value = "ap-south"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "Japan (Tokyo)"
    value = "ap-northeast"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Australia (Sydney)"
    value = "ap-southeast"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "India (Mumbai)"
    value = "ap-west"
    icon  = "/emojis/1f1ee-1f1f3.png"
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
  default      = "linode/ubuntu22.04"
  type         = "string"
  mutable      = false
  
  option {
    name  = "Ubuntu 22.04 LTS"
    value = "linode/ubuntu22.04"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Ubuntu 20.04 LTS"
    value = "linode/ubuntu20.04"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Debian 12"
    value = "linode/debian12"
    icon  = "/icon/debian.svg"
  }
  option {
    name  = "Debian 11"
    value = "linode/debian11"
    icon  = "/icon/debian.svg"
  }
  option {
    name  = "CentOS Stream 9"
    value = "linode/centos-stream9"
    icon  = "/icon/centos.svg"
  }
  option {
    name  = "Fedora 39"
    value = "linode/fedora39"
    icon  = "/icon/fedora.svg"
  }
  option {
    name  = "Fedora 38"
    value = "linode/fedora38"
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
  display_name = "Home Volume Size"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = "20"
  mutable      = false
  
  validation {
    min = 10
    max = 1024
  }
}

resource "linode_volume" "home_volume" {
  label  = "coder-${data.coder_workspace.me.id}-home"
  size   = data.coder_parameter.home_volume_size.value
  region = data.coder_parameter.region.value

  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
}

resource "linode_instance" "workspace" {
  count  = data.coder_workspace.me.start_count
  label  = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  image  = data.coder_parameter.instance_image.value
  type   = data.coder_parameter.instance_type.value
  region = data.coder_parameter.region.value

  # Configure metadata for cloud-init
  metadata {
    user_data = base64encode(templatefile("cloud-config.yaml.tftpl", {
      username          = lower(data.coder_workspace_owner.me.name)
      home_volume_label = linode_volume.home_volume.label
      init_script       = base64encode(coder_agent.main.init_script)
      coder_agent_token = coder_agent.main.token
    }))
  }
}

# Attach the volume to the instance
resource "linode_volume_attachment" "workspace_volume" {
  count       = data.coder_workspace.me.start_count
  linode_id   = linode_instance.workspace[0].id
  volume_id   = linode_volume.home_volume.id
}

resource "coder_metadata" "workspace-info" {
  count       = data.coder_workspace.me.start_count
  resource_id = linode_instance.workspace[0].id

  item {
    key   = "region"
    value = linode_instance.workspace[0].region
  }
  item {
    key   = "image"
    value = linode_instance.workspace[0].image
  }
  item {
    key   = "type"
    value = linode_instance.workspace[0].type
  }
}

resource "coder_metadata" "volume-info" {
  resource_id = linode_volume.home_volume.id

  item {
    key   = "size"
    value = "${linode_volume.home_volume.size} GB"
  }
}
