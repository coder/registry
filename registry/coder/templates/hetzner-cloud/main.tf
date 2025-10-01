terraform {
  required_version = ">= 1.4.0"

  required_providers {
    coder = {
      source = "coder/coder"
    }
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

provider "coder" {}

variable "hcloud_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = <<-EOF
    Hetzner Cloud API token. It is recommended to supply this via the HCLOUD_TOKEN
    environment variable when starting coderd instead of setting the variable directly.
  EOF
}

provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : null
}

locals {
  owner_name         = lower(replace(data.coder_workspace_owner.me.name, "[^a-zA-Z0-9-]", "-"))
  workspace_name     = lower(replace(data.coder_workspace.me.name, "[^a-zA-Z0-9-]", "-"))
  server_name        = substr("coder-${local.owner_name}-${local.workspace_name}", 0, 63)
  username           = local.owner_name != "" ? local.owner_name : "coder"
  home_volume_label  = "coder-home"
  network_zones      = {
    nbg1 = "eu-central"
    fsn1 = "eu-central"
    hel1 = "eu-central"
    ash  = "us-east"
    hil  = "us-west"
  }
  network_zone = lookup(local.network_zones, data.coder_parameter.location.value, "eu-central")
}

# Workspace parameters exposed in the Coder UI

data "coder_parameter" "location" {
  name         = "hcloud_location"
  display_name = "Hetzner location"
  description  = "Region where the server will be created."
  default      = "nbg1"
  mutable      = false
  option {
    name  = "Germany (Nuremberg)"
    value = "nbg1"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "Germany (Falkenstein)"
    value = "fsn1"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "Finland (Helsinki)"
    value = "hel1"
    icon  = "/emojis/1f1eb-1f1ee.png"
  }
  option {
    name  = "United States (Ashburn)"
    value = "ash"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (Hillsboro)"
    value = "hil"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
}

data "coder_parameter" "server_type" {
  name         = "hcloud_server_type"
  display_name = "Server type"
  description  = "Hetzner instance size. Prices are per hour."
  default      = "cpx21"
  mutable      = false
  option {
    name  = "CPX11 – 2 vCPU, 2 GB RAM"
    value = "cpx11"
  }
  option {
    name  = "CPX21 – 3 vCPU, 4 GB RAM"
    value = "cpx21"
  }
  option {
    name  = "CPX31 – 4 vCPU, 8 GB RAM"
    value = "cpx31"
  }
  option {
    name  = "CPX41 – 8 vCPU, 16 GB RAM"
    value = "cpx41"
  }
  option {
    name  = "CAX11 (ARM) – 2 vCPU, 2 GB RAM"
    value = "cax11"
  }
  option {
    name  = "CAX21 (ARM) – 4 vCPU, 8 GB RAM"
    value = "cax21"
  }
}

data "coder_parameter" "image" {
  name         = "hcloud_image"
  display_name = "Server image"
  description  = "Operating system image for the workspace."
  default      = "ubuntu-22.04"
  mutable      = false
  option {
    name  = "Ubuntu 24.04 LTS"
    value = "ubuntu-24.04"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Ubuntu 22.04 LTS"
    value = "ubuntu-22.04"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Debian 12"
    value = "debian-12"
    icon  = "/icon/debian.svg"
  }
  option {
    name  = "Fedora 40"
    value = "fedora-40"
    icon  = "/icon/fedora.svg"
  }
  option {
    name  = "Rocky Linux 9"
    value = "rocky-9"
    icon  = "/icon/rockylinux.svg"
  }
}

data "coder_parameter" "volume_size" {
  name         = "home_volume_size"
  display_name = "Home volume size"
  description  = "Size of the persistent home volume (GiB)."
  type         = "number"
  default      = "50"
  mutable      = false
  validation {
    min = 10
    max = 1024
  }
}

data "coder_parameter" "network_cidr" {
  name         = "network_cidr"
  display_name = "Private network CIDR"
  description  = "CIDR block for the workspace private network."
  default      = "10.20.0.0/16"
  mutable      = false
}

data "coder_parameter" "subnet_cidr" {
  name         = "subnet_cidr"
  display_name = "Subnet CIDR"
  description  = "Subnet used for the workspace server. Must be within the private network CIDR."
  default      = "10.20.1.0/24"
  mutable      = false
}

# Coder workspace metadata

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  startup_script = <<-EOT
    set -e

    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Install basic packages used in most development workflows
    if command -v apt >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y build-essential curl git
    fi
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

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
    display_name = "Home Disk"
    interval     = 600
    timeout      = 30
    script       = "coder stat disk --path /home/${local.username}"
  }

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    web_terminal           = true
    port_forwarding_helper = true
  }
}

module "code_server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/modules/coder/code-server/coder"
  version = "~> 1.0"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  order      = 1
}

module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/${local.username}"
}

resource "hcloud_network" "workspace" {
  name     = "coder-${data.coder_workspace.me.id}-network"
  ip_range = data.coder_parameter.network_cidr.value
  labels = {
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
  }
}

resource "hcloud_network_subnet" "workspace" {
  network_id   = hcloud_network.workspace.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = data.coder_parameter.subnet_cidr.value
}

resource "hcloud_firewall" "workspace" {
  name = "coder-${data.coder_workspace.me.id}-firewall"

  rule {
    direction   = "in"
    description = "Allow SSH"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction   = "in"
    description = "Allow HTTPS"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction   = "in"
    description = "Allow HTTP"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction        = "out"
    description      = "Allow all TCP egress"
    protocol         = "tcp"
    port             = "0-65535"
    destination_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction        = "out"
    description      = "Allow all UDP egress"
    protocol         = "udp"
    port             = "0-65535"
    destination_ips  = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_volume" "home_volume" {
  name      = "coder-${data.coder_workspace.me.id}-home"
  size      = data.coder_parameter.volume_size.value
  location  = data.coder_parameter.location.value
  format    = "ext4"
  automount = false
  labels = {
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
    "coder.owner"          = data.coder_workspace_owner.me.name
  }
}

resource "hcloud_server" "workspace" {
  count       = data.coder_workspace.me.start_count
  name        = local.server_name
  image       = data.coder_parameter.image.value
  server_type = data.coder_parameter.server_type.value
  location    = data.coder_parameter.location.value
  firewall_ids = [hcloud_firewall.workspace.id]
  volume_ids   = [hcloud_volume.home_volume.id]

  public_net {
    enable_ipv4 = true
    enable_ipv6 = true
  }

  network {
    network_id = hcloud_network.workspace.id
    ip         = cidrhost(data.coder_parameter.subnet_cidr.value, 10)
  }

  user_data = templatefile("${path.module}/cloud-config.yaml.tftpl", {
    username          = local.username
    home_volume_label = local.home_volume_label
    volume_device     = hcloud_volume.home_volume.linux_device
    init_script       = base64encode(coder_agent.main.init_script)
    coder_agent_token = coder_agent.main.token
  })

  labels = {
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
    "coder.owner"          = data.coder_workspace_owner.me.name
  }

  depends_on = [
    hcloud_network_subnet.workspace
  ]
}

resource "coder_metadata" "server" {
  count       = length(hcloud_server.workspace) > 0 ? 1 : 0
  resource_id = hcloud_server.workspace[0].id

  item {
    key   = "location"
    value = data.coder_parameter.location.value
  }

  item {
    key   = "server_type"
    value = data.coder_parameter.server_type.value
  }

  item {
    key   = "image"
    value = data.coder_parameter.image.value
  }
}

resource "coder_metadata" "volume" {
  resource_id = hcloud_volume.home_volume.id

  item {
    key   = "size"
    value = "${hcloud_volume.home_volume.size} GiB"
  }
}

resource "coder_metadata" "network" {
  resource_id = hcloud_network.workspace.id

  item {
    key   = "cidr"
    value = data.coder_parameter.network_cidr.value
  }
  item {
    key   = "subnet"
    value = data.coder_parameter.subnet_cidr.value
  }
}
