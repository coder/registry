terraform {
  required_version = ">= 1.6"
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
    tls = {
      source = "hashicorp/tls"
    }
  }
}

provider "coder" {}

variable "tenancy_ocid" {
  type        = string
  description = "The tenancy OCID used to query availability domains."
}

variable "compartment_ocid" {
  type        = string
  description = "The compartment OCID where resources will be provisioned."
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "OCI region"
  description  = "Which OCI region should your workspace use?"
  default      = "us-ashburn-1"
  mutable      = false
  option {
    name  = "US Ashburn (us-ashburn-1)"
    value = "us-ashburn-1"
  }
  option {
    name  = "US Phoenix (us-phoenix-1)"
    value = "us-phoenix-1"
  }
  option {
    name  = "UK London (uk-london-1)"
    value = "uk-london-1"
  }
  option {
    name  = "Germany Frankfurt (eu-frankfurt-1)"
    value = "eu-frankfurt-1"
  }
}

data "coder_parameter" "shape" {
  name         = "shape"
  display_name = "Instance shape"
  description  = "Which OCI shape should your workspace use?"
  default      = "VM.Standard.E3.Flex"
  mutable      = false
  option {
    name  = "VM.Standard.E3.Flex (AMD, flexible)"
    value = "VM.Standard.E3.Flex"
  }
  option {
    name  = "VM.Standard.E4.Flex (AMD, flexible)"
    value = "VM.Standard.E4.Flex"
  }
  option {
    name  = "VM.Standard.A1.Flex (Arm, flexible)"
    value = "VM.Standard.A1.Flex"
  }
}

data "coder_parameter" "ocpus" {
  name         = "ocpus"
  display_name = "OCPUs"
  description  = "Number of OCPUs for flex shapes."
  type         = "number"
  default      = 1
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory_gbs" {
  name         = "memory_gbs"
  display_name = "Memory (GB)"
  description  = "Memory in GB for flex shapes."
  type         = "number"
  default      = 6
  validation {
    min = 1
    max = 64
  }
}

data "coder_parameter" "boot_volume_size" {
  name         = "boot_volume_size"
  display_name = "Boot volume size"
  description  = "Boot volume size in GB."
  type         = "number"
  default      = 50
  validation {
    min = 50
    max = 1024
  }
}

provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = data.coder_parameter.shape.value
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
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
  source = "registry.coder.com/coder/code-server/coder"

  version = "~> 1.0"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  order      = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"
}

locals {
  prefix     = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  linux_user = "coder"
  is_flex    = endswith(data.coder_parameter.shape.value, "Flex")
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      linux_user        = local.linux_user
      init_script       = base64encode(coder_agent.main.init_script)
      coder_agent_token = coder_agent.main.token
    })
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "${local.prefix}-vcn"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.prefix}-igw"
  enabled        = true
}

resource "oci_core_route_table" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.prefix}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

resource "oci_core_security_list" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.prefix}-sl"

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

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "main" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "${local.prefix}-subnet"
  route_table_id    = oci_core_route_table.main.id
  security_list_ids = [oci_core_security_list.main.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_instance" "workspace" {
  count               = data.coder_workspace.me.start_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = local.prefix
  shape               = data.coder_parameter.shape.value

  dynamic "shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = data.coder_parameter.ocpus.value
      memory_in_gbs = data.coder_parameter.memory_gbs.value
    }
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    image_id                = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = data.coder_parameter.boot_volume_size.value
  }

  metadata = {
    ssh_authorized_keys = tls_private_key.ssh.public_key_openssh
    user_data           = base64encode(data.cloudinit_config.user_data.rendered)
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = oci_core_instance.workspace[0].id

  item {
    key   = "shape"
    value = oci_core_instance.workspace[0].shape
  }
}

resource "coder_metadata" "boot_volume" {
  count       = data.coder_workspace.me.start_count
  resource_id = oci_core_instance.workspace[0].id

  item {
    key   = "boot_volume"
    value = "${data.coder_parameter.boot_volume_size.value} GiB"
  }
}
