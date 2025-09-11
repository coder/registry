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
  description = "The OCID of the compartment to create resources in. If empty, defaults to tenancy OCID (root compartment)."
  type        = string
  default     = ""
}

variable "tenancy_ocid" {
  description = "Tenancy OCID used as the root compartment when compartment_ocid is unset. Typically set from environment (OCI_TENANCY_OCID)."
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
  default      = "VM.Standard.E2.1.Micro"
  mutable      = false
  option {
    name  = "VM.Standard.A1.Flex (1 OCPU, 6 GB RAM)"
    value = "VM.Standard.A1.Flex-1-6"
  }
  option {
    name  = "VM.Standard.A1.Flex (2 OCPU, 12 GB RAM)"
    value = "VM.Standard.A1.Flex-2-12"
  }
  option {
    name  = "VM.Standard.A1.Flex (4 OCPU, 24 GB RAM)"
    value = "VM.Standard.A1.Flex-4-24"
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
    value = "VM.Standard.E3.Flex-1-8"
  }
  option {
    name  = "VM.Standard.E3.Flex (2 OCPU, 16 GB RAM)"
    value = "VM.Standard.E3.Flex-2-16"
  }
  option {
    name  = "VM.Standard.E3.Flex (4 OCPU, 32 GB RAM)"
    value = "VM.Standard.E3.Flex-4-32"
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

# Determine effective compartment (defaults to tenancy/root when not provided)
locals {
  effective_compartment_ocid = length(trimspace(var.compartment_ocid)) > 0 ? var.compartment_ocid : var.tenancy_ocid
}

# Validate we have an effective compartment id
locals {
  compartment_id = local.effective_compartment_ocid
}

# Early, friendly validation to avoid opaque 401s from the OCI APIs
resource "null_resource" "validate_configuration" {
  lifecycle {
    precondition {
      condition     = length(trimspace(local.compartment_id)) > 0
      error_message = "Provide either 'compartment_ocid' or 'tenancy_ocid'. For containerized coderd, set TF_VAR_tenancy_ocid or mount ~/.oci/config and set OCI_* envs."
    }
  }
}

# Get the latest Ubuntu image
data "oci_core_images" "ubuntu" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"

  # Parse shape configuration for flexible shapes
  shape_parts = split("-", data.coder_parameter.instance_shape.value)
  base_shape  = length(local.shape_parts) > 2 ? join("-", slice(local.shape_parts, 0, 3)) : data.coder_parameter.instance_shape.value
  ocpus       = length(local.shape_parts) > 3 ? tonumber(local.shape_parts[3]) : 1
  memory_gb   = length(local.shape_parts) > 4 ? tonumber(local.shape_parts[4]) : 6

  # Determine if shape is flexible (needs shape_config)
  is_flexible = can(regex(".*Flex.*", local.base_shape))
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
      coder_agent_token = coder_agent.dev[0].token
    })
  }

  part {
    filename     = "userdata.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      hostname          = local.hostname
      linux_user        = local.linux_user
      coder_agent_token = coder_agent.dev[0].token
    })
  }
}

# VCN
resource "oci_core_vcn" "vcn" {
  compartment_id = local.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "coder-vcn-${data.coder_workspace.me.id}"
  dns_label      = "coder${data.coder_workspace.me.id}"
}

# Internet Gateway
resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "coder-internet-gateway-${data.coder_workspace.me.id}"
}

# Route Table
resource "oci_core_route_table" "route_table" {
  compartment_id = local.compartment_id
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
  compartment_id = local.compartment_id
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
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = "10.0.1.0/24"
  display_name   = "coder-subnet-${data.coder_workspace.me.id}"
  dns_label      = "coder${data.coder_workspace.me.id}"

  security_list_ids = [oci_core_security_list.security_list.id]
  route_table_id    = oci_core_route_table.route_table.id
}

# Home disk
resource "oci_core_volume" "home_volume" {
  compartment_id      = local.compartment_id
  display_name        = "coder-${data.coder_workspace.me.id}-home"
  size_in_gbs         = data.coder_parameter.home_size.value
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

# OCI Instance
resource "oci_core_instance" "dev" {
  count               = data.coder_workspace.me.start_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  shape               = local.base_shape

  dynamic "shape_config" {
    for_each = local.is_flexible ? [1] : []
    content {
      ocpus         = local.ocpus
      memory_in_gbs = local.memory_gb
    }
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
  compartment_id  = local.compartment_id
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
