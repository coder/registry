terraform {
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

# Variable for Hetzner Cloud API token
variable "hcloud_token" {
  description = "Hetzner Cloud API token for authentication"
  type        = string
  sensitive   = true
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Load Hetzner Cloud configuration from JSON
locals {
  hetzner_config = jsondecode(file("${path.module}/hetzner-config.json"))
}

# Hetzner Cloud locations parameter (dynamically generated from JSON)
data "coder_parameter" "location" {
  name         = "location"
  display_name = "Location"
  description  = "This is the location where your workspace will be created."
  icon         = "/emojis/1f30e.png"
  type         = "string"
  default      = "fsn1"
  mutable      = false

  dynamic "option" {
    for_each = local.hetzner_config.type_meta.locations
    content {
      name  = option.value.name
      value = option.key
      icon  = "/emojis/1f30e.png"
    }
  }
}


# Hetzner Cloud server types parameter (dynamically generated from JSON)
data "coder_parameter" "server_type" {
  name         = "server_type"
  display_name = "Server Type"
  description  = "Which Hetzner Cloud server type would you like to use?"
  default      = "cx22"
  type         = "string"
  icon         = "/icon/memory.svg"
  mutable      = false

  dynamic "option" {
    for_each = local.hetzner_config.type_meta.server_types
    content {
      name  = option.value.name
      value = option.key
    }
  }
}

# Server image parameter (dynamically generated from JSON)
data "coder_parameter" "server_image" {
  name         = "server_image"
  display_name = "Server Image"
  description  = "Which operating system image would you like to use?"
  default      = "ubuntu-22.04"
  type         = "string"
  mutable      = false

  dynamic "option" {
    for_each = local.hetzner_config.type_meta.images
    content {
      name  = option.value.name
      value = option.key
      icon  = option.value.icon
    }
  }

}

# Optional custom image override
data "coder_parameter" "custom_image_override" {
  name         = "custom_image_override"
  display_name = "Custom Image Override (optional)"
  description  = "Leave empty to use the selected image above, or enter a custom Hetzner Cloud image name to override (e.g., 'my-custom-snapshot', 'debian-12-amd64')"
  type         = "string"
  default      = ""
  mutable      = false
}

# Determine which image to use - custom override takes precedence
locals {
  final_image = data.coder_parameter.custom_image_override.value != "" ? data.coder_parameter.custom_image_override.value : data.coder_parameter.server_image.value
}

# Home volume size parameter
data "coder_parameter" "volume_size" {
  name         = "volume_size"
  display_name = "Home Volume Size (GB)"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = 20
  mutable      = true

  validation {
    min       = 10
    max       = 1000
    monotonic = "increasing"
  }
}

locals {
  # Ensure unique names by including workspace ID
  server_name   = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-${substr(data.coder_workspace.me.id, 0, 8)}"
  volume_name   = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-${substr(data.coder_workspace.me.id, 0, 8)}-home"
  network_name  = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-${substr(data.coder_workspace.me.id, 0, 8)}-net"
  firewall_name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-${substr(data.coder_workspace.me.id, 0, 8)}-fw"

  # Get selected server type and location configuration
  selected_server_type = local.hetzner_config.type_meta.server_types[data.coder_parameter.server_type.value]
  selected_location    = local.hetzner_config.type_meta.locations[data.coder_parameter.location.value]
  network_zone         = local.selected_location.zone

  # Get availability for selected server type (use specific or wildcard)
  server_availability = lookup(local.hetzner_config.availability, data.coder_parameter.server_type.value, local.hetzner_config.availability["*"])

  # Validate server type is available in selected location
  is_valid_combination = contains(local.server_availability, data.coder_parameter.location.value)
}

# Validation check for server type and location compatibility
resource "null_resource" "validate_server_location" {
  count = local.is_valid_combination ? 0 : 1

  provisioner "local-exec" {
    command = "echo 'ERROR: Server type ${data.coder_parameter.server_type.value} is not available in location ${data.coder_parameter.location.value}' && exit 1"
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

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
}

variable "ssh_key_id" {
  type        = number
  description = <<-EOF
    Hetzner Cloud SSH key ID (obtain via the Hetzner Cloud Console or CLI):

    Can be set to "0" for no SSH key.

      $ hcloud ssh-key list
  EOF
  sensitive   = true

  validation {
    condition     = var.ssh_key_id >= 0
    error_message = "Invalid Hetzner Cloud SSH key ID, a number is required."
  }
}

# Create private network
resource "hcloud_network" "workspace" {
  name     = local.network_name
  ip_range = "10.0.0.0/16"

  labels = {
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.resource"  = "network"
  }
}

# Create network subnet
resource "hcloud_network_subnet" "workspace" {
  network_id   = hcloud_network.workspace.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = "10.0.1.0/24"
}

# Create firewall
resource "hcloud_firewall" "workspace" {
  name = local.firewall_name

  labels = {
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.resource"  = "firewall"
  }

  rule {
    direction  = "in"
    port       = "22"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    port       = "80"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    port       = "443"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    port       = "8080"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Create volume for home directory
resource "hcloud_volume" "home_volume" {
  name     = local.volume_name
  size     = data.coder_parameter.volume_size.value
  location = data.coder_parameter.location.value
  format   = "ext4"

  labels = {
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.resource"  = "home-volume"
  }

  # Protect the volume from being deleted due to changes in attributes
  lifecycle {
    ignore_changes = all
  }
}

# Create the server
resource "hcloud_server" "workspace" {
  count        = data.coder_workspace.me.start_count
  name         = local.server_name
  server_type  = data.coder_parameter.server_type.value
  image        = local.final_image
  location     = data.coder_parameter.location.value
  ssh_keys     = var.ssh_key_id > 0 ? [var.ssh_key_id] : []
  firewall_ids = [hcloud_firewall.workspace.id]

  labels = {
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.resource"  = "workspace-server"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.workspace.id
    ip         = "10.0.1.5"
  }

  user_data = templatefile("${path.module}/cloud-config.yaml.tftpl", {
    hostname          = local.server_name
    username          = lower(data.coder_workspace_owner.me.name)
    volume_device     = "/dev/sdb"
    init_script       = base64encode(coder_agent.main.init_script)
    coder_agent_token = coder_agent.main.token
  })

  depends_on = [
    hcloud_network_subnet.workspace
  ]

  # Proper lifecycle: server is destroyed when workspace stops, but volume persists
  lifecycle {
    ignore_changes = [ssh_keys, user_data]
  }
}

# Attach volume to server
resource "hcloud_volume_attachment" "home_volume" {
  count     = data.coder_workspace.me.start_count
  volume_id = hcloud_volume.home_volume.id
  server_id = hcloud_server.workspace[0].id
  automount = true
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = hcloud_server.workspace[0].id

  item {
    key   = "location"
    value = "${local.selected_location.name} (${hcloud_server.workspace[0].location})"
  }
  item {
    key   = "server_type"
    value = "${local.selected_server_type.name} (${hcloud_server.workspace[0].server_type})"
  }
  item {
    key   = "vcpus"
    value = local.selected_server_type.vcpus
  }
  item {
    key   = "memory"
    value = "${local.selected_server_type.memory} GB"
  }
  item {
    key   = "image"
    value = data.coder_parameter.custom_image_override.value != "" ? data.coder_parameter.custom_image_override.value : local.hetzner_config.type_meta.images[data.coder_parameter.server_image.value].name
  }
  item {
    key   = "public_ipv4"
    value = hcloud_server.workspace[0].ipv4_address
  }
}

resource "coder_metadata" "volume_info" {
  resource_id = hcloud_volume.home_volume.id

  item {
    key   = "size"
    value = "${hcloud_volume.home_volume.size} GB"
  }
  item {
    key   = "location"
    value = hcloud_volume.home_volume.location
  }
}
