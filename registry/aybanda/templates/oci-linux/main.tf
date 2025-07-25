terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    oci = {
      source = "oracle/oci"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}

# Variables
variable "compartment_ocid" {
  description = "The OCID of the compartment to create resources in"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the instance"
  type        = string
  default     = ""
}

# OCI Region parameter
data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The region to deploy the workspace in."
  default      = "us-ashburn-1"
  mutable      = false
  option {
    name  = "US East (Ashburn)"
    value = "us-ashburn-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US West (Phoenix)"
    value = "us-phoenix-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Canada Southeast (Montreal)"
    value = "ca-montreal-1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "UK South (London)"
    value = "uk-london-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Germany Central (Frankfurt)"
    value = "eu-frankfurt-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Netherlands Northwest (Amsterdam)"
    value = "eu-amsterdam-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Switzerland North (Zurich)"
    value = "eu-zurich-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Japan East (Tokyo)"
    value = "ap-tokyo-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Japan Central (Osaka)"
    value = "ap-osaka-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "South Korea Central (Seoul)"
    value = "ap-seoul-1"
    icon  = "/emojis/1f1f0-1f1f7.png"
  }
  option {
    name  = "Australia Southeast (Sydney)"
    value = "ap-sydney-1"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "India West (Mumbai)"
    value = "ap-mumbai-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "India South (Hyderabad)"
    value = "ap-hyderabad-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Saudi Arabia West (Jeddah)"
    value = "me-jeddah-1"
    icon  = "/emojis/1f1f8-1f1e6.png"
  }
  option {
    name  = "UAE East (Dubai)"
    value = "me-dubai-1"
    icon  = "/emojis/1f1e6-1f1ea.png"
  }
  option {
    name  = "Brazil East (São Paulo)"
    value = "sa-saopaulo-1"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
  option {
    name  = "Chile (Santiago)"
    value = "sa-santiago-1"
    icon  = "/emojis/1f1e8-1f1f1.png"
  }
}

# Instance shape parameter
data "coder_parameter" "instance_shape" {
  name         = "instance_shape"
  display_name = "Instance Shape"
  description  = "What instance shape should your workspace use?"
  default      = "VM.Standard.A1.Flex"
  mutable      = false
  option {
    name  = "VM.Standard.A1.Flex (1 OCPU, 6 GB RAM)"
    value = "VM.Standard.A1.Flex"
  }
  option {
    name  = "VM.Standard.A1.Flex (2 OCPU, 12 GB RAM)"
    value = "VM.Standard.A1.Flex"
  }
  option {
    name  = "VM.Standard.A1.Flex (4 OCPU, 24 GB RAM)"
    value = "VM.Standard.A1.Flex"
  }
  option {
    name  = "VM.Standard.E2.1.Micro (1 OCPU, 1 GB RAM)"
    value = "VM.Standard.E2.1.Micro"
  }
  option {
    name  = "VM.Standard.E2.1.Small (1 OCPU, 2 GB RAM)"
    value = "VM.Standard.E2.1.Small"
  }
  option {
    name  = "VM.Standard.E2.1.Medium (1 OCPU, 4 GB RAM)"
    value = "VM.Standard.E2.1.Medium"
  }
  option {
    name  = "VM.Standard.E2.2.Medium (2 OCPU, 8 GB RAM)"
    value = "VM.Standard.E2.2.Medium"
  }
  option {
    name  = "VM.Standard.E2.4.Medium (4 OCPU, 16 GB RAM)"
    value = "VM.Standard.E2.4.Medium"
  }
  option {
    name  = "VM.Standard.E3.Flex (1 OCPU, 8 GB RAM)"
    value = "VM.Standard.E3.Flex"
  }
  option {
    name  = "VM.Standard.E3.Flex (2 OCPU, 16 GB RAM)"
    value = "VM.Standard.E3.Flex"
  }
  option {
    name  = "VM.Standard.E3.Flex (4 OCPU, 32 GB RAM)"
    value = "VM.Standard.E3.Flex"
  }
}

# Home disk size parameter
data "coder_parameter" "home_size" {
  name         = "home_size"
  display_name = "Home Disk Size"
  description  = "How large should the home disk be?"
  default      = "50"
  mutable      = false
  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
  option {
    name  = "200 GB"
    value = "200"
  }
  option {
    name  = "500 GB"
    value = "500"
  }
  option {
    name  = "1 TB"
    value = "1024"
  }
}

# OCI Provider configuration
provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Get the compartment OCID from environment variable
data "oci_identity_compartments" "compartments" {
  compartment_id = var.compartment_ocid
  access_level   = "ACCESSIBLE"
  state          = "ACTIVE"
}

# Get the latest Ubuntu image
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"
}

# Coder Agent
resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  auth           = "token"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here
  EOT

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
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path $HOME"
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.dev[0].id
  order    = 1
}

# See https://registry.coder.com/modules/jetbrains-gateway
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/jetbrains-gateway/coder"

  # JetBrains IDEs to make available for the user to select
  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "IU"

  # Default folder to open when starting a JetBrains IDE
  folder = "/home/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  order      = 2
}

# Cloud-init configuration
data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  boundary = "//"

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      hostname          = local.hostname
      linux_user        = local.linux_user
      ssh_public_key    = var.ssh_public_key
      coder_agent_token = coder_agent.dev[0].token
    })
  }

  part {
    filename     = "userdata.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      hostname          = local.hostname
      linux_user        = local.linux_user
      ssh_public_key    = var.ssh_public_key
      coder_agent_token = coder_agent.dev[0].token
    })
  }
}

# VCN
resource "oci_core_vcn" "vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "coder-vcn-${data.coder_workspace.me.id}"
  dns_label      = "coder${data.coder_workspace.me.id}"
}

# Internet Gateway
resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "coder-internet-gateway-${data.coder_workspace.me.id}"
}

# Route Table
resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "coder-route-table-${data.coder_workspace.me.id}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

# Security List
resource "oci_core_security_list" "security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "coder-security-list-${data.coder_workspace.me.id}"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }
}

# Subnet
resource "oci_core_subnet" "subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = "10.0.1.0/24"
  display_name   = "coder-subnet-${data.coder_workspace.me.id}"
  dns_label      = "coder${data.coder_workspace.me.id}"

  security_list_ids = [oci_core_security_list.security_list.id]
  route_table_id    = oci_core_route_table.route_table.id
}

# Home disk
resource "oci_core_volume" "home_volume" {
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${data.coder_workspace.me.id}-home"
  size_in_gbs         = data.coder_parameter.home_size.value
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# OCI Instance
resource "oci_core_instance" "dev" {
  count               = data.coder_workspace.me.start_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  shape               = data.coder_parameter.instance_shape.value

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(data.cloudinit_config.user_data.rendered)
  }

  freeform_tags = {
    "Coder_Provisioned" = "true"
  }
}

# Attach home volume
resource "oci_core_volume_attachment" "home_attachment" {
  count           = data.coder_workspace.me.start_count
  attachment_type = "paravirtualized"
  compartment_id  = var.compartment_ocid
  instance_id     = oci_core_instance.dev[0].id
  volume_id       = oci_core_volume.home_volume.id
}

# Workspace metadata
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = oci_core_instance.dev[0].id

  item {
    key   = "type"
    value = oci_core_instance.dev[0].shape
  }
  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
}

resource "coder_metadata" "home_info" {
  resource_id = oci_core_volume.home_volume.id

  item {
    key   = "size"
    value = "${data.coder_parameter.home_size.value} GiB"
  }
} 
