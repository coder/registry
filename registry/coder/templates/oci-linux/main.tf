terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# OCI Region selection
data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The OCI region to deploy the workspace in."
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
    name  = "US West (San Jose)"
    value = "us-sanjose-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Germany Central (Frankfurt)"
    value = "eu-frankfurt-1"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "UK South (London)"
    value = "uk-london-1"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "Japan East (Tokyo)"
    value = "ap-tokyo-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Australia East (Sydney)"
    value = "ap-sydney-1"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Brazil East (Sao Paulo)"
    value = "sa-saopaulo-1"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
}

data "coder_parameter" "instance_shape" {
  name         = "instance_shape"
  display_name = "Instance shape"
  description  = "What instance shape should your workspace use?"
  default      = "VM.Standard.E4.Flex"
  mutable      = false
  option {
    name  = "AMD Flex (1 OCPU, 6 GB RAM)"
    value = "VM.Standard.E4.Flex"
  }
  option {
    name  = "AMD Flex (2 OCPU, 12 GB RAM)"
    value = "VM.Standard.E4.Flex-2"
  }
  option {
    name  = "AMD Flex (4 OCPU, 24 GB RAM)"
    value = "VM.Standard.E4.Flex-4"
  }
  option {
    name  = "Ampere (1 OCPU, 6 GB RAM)"
    value = "VM.Standard.A1.Flex"
  }
  option {
    name  = "Ampere (2 OCPU, 12 GB RAM)"
    value = "VM.Standard.A1.Flex-2"
  }
  option {
    name  = "Ampere (4 OCPU, 24 GB RAM)"
    value = "VM.Standard.A1.Flex-4"
  }
}

locals {
  # Parse the instance shape to extract OCPUs and memory
  shape_parts = split("-", data.coder_parameter.instance_shape.value)
  base_shape  = length(local.shape_parts) > 1 ? join("-", slice(local.shape_parts, 0, length(local.shape_parts) - 1)) : data.coder_parameter.instance_shape.value
  ocpus       = length(local.shape_parts) > 1 ? tonumber(local.shape_parts[length(local.shape_parts) - 1]) : 1
  memory_in_gbs = local.ocpus * 6

  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"

  # Determine architecture based on shape
  arch = startswith(data.coder_parameter.instance_shape.value, "VM.Standard.A1") ? "arm64" : "amd64"
}

provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Get the availability domain
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Get the latest Oracle Linux image
data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = local.base_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Oracle-Linux-8\\.[0-9]+-[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9]+$"]
    regex  = true
  }
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment to create resources in"
}

variable "vcn_ocid" {
  type        = string
  description = "The OCID of an existing VCN to use (optional - creates new VCN if not provided)"
  default     = ""
}

variable "subnet_ocid" {
  type        = string
  description = "The OCID of an existing subnet to use (optional - creates new subnet if not provided)"
  default     = ""
}

# Create VCN if not provided
resource "oci_core_vcn" "coder_vcn" {
  count          = var.vcn_ocid == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "coder-vcn-${data.coder_workspace_owner.me.name}"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "codervcn"
}

resource "oci_core_internet_gateway" "coder_igw" {
  count          = var.vcn_ocid == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn[0].id
  display_name   = "coder-igw"
  enabled        = true
}

resource "oci_core_route_table" "coder_rt" {
  count          = var.vcn_ocid == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn[0].id
  display_name   = "coder-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.coder_igw[0].id
  }
}

resource "oci_core_security_list" "coder_sl" {
  count          = var.vcn_ocid == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn[0].id
  display_name   = "coder-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "coder_subnet" {
  count                      = var.subnet_ocid == "" ? 1 : 0
  compartment_id             = var.compartment_ocid
  vcn_id                     = var.vcn_ocid != "" ? var.vcn_ocid : oci_core_vcn.coder_vcn[0].id
  display_name               = "coder-subnet-${data.coder_workspace_owner.me.name}"
  cidr_block                 = "10.0.1.0/24"
  dns_label                  = "codersubnet"
  prohibit_public_ip_on_vnic = false
  route_table_id             = var.vcn_ocid != "" ? null : oci_core_route_table.coder_rt[0].id
  security_list_ids          = var.vcn_ocid != "" ? null : [oci_core_security_list.coder_sl[0].id]
}

locals {
  subnet_id = var.subnet_ocid != "" ? var.subnet_ocid : oci_core_subnet.coder_subnet[0].id
}

resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = local.arch
  auth           = "token"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Add any commands that should be executed at workspace startup here
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
    interval     = 600
    timeout      = 30
    script       = "coder stat disk --path $HOME"
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  version = "~> 1.0"

  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  order      = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  folder     = "/home/coder"
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = true

  boundary = "//"

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      hostname   = local.hostname
      linux_user = local.linux_user
    })
  }

  part {
    filename     = "userdata.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      linux_user = local.linux_user

      init_script = try(coder_agent.dev[0].init_script, "")
    })
  }
}

resource "oci_core_instance" "dev" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  shape               = local.base_shape

  dynamic "shape_config" {
    for_each = can(regex("Flex", local.base_shape)) ? [1] : []
    content {
      ocpus         = local.ocpus
      memory_in_gbs = local.memory_in_gbs
    }
  }

  create_vnic_details {
    subnet_id                 = local.subnet_id
    display_name              = "primary-vnic"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = local.hostname
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    user_data = data.cloudinit_config.user_data.rendered
  }

  freeform_tags = {
    "Coder_Provisioned" = "true"
    "Coder_Workspace"   = data.coder_workspace.me.name
    "Coder_Owner"       = data.coder_workspace_owner.me.name
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = oci_core_instance.dev.id
  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "shape"
    value = local.base_shape
  }
  item {
    key   = "ocpus"
    value = local.ocpus
  }
  item {
    key   = "memory"
    value = "${local.memory_in_gbs} GB"
  }
}

# Start/stop the instance based on workspace state
resource "null_resource" "instance_state" {
  triggers = {
    instance_id = oci_core_instance.dev.id
    state       = data.coder_workspace.me.transition
  }

  provisioner "local-exec" {
    command = data.coder_workspace.me.transition == "start" ? "oci compute instance action --instance-id ${oci_core_instance.dev.id} --action START --wait-for-state RUNNING 2>/dev/null || true" : "oci compute instance action --instance-id ${oci_core_instance.dev.id} --action STOP --wait-for-state STOPPED 2>/dev/null || true"
  }
}
