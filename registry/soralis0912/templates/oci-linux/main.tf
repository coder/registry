terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    oci = {
      source = "oracle/oci"
    }
  }
}

provider "coder" {}

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
    name  = "Canada Southeast (Toronto)"
    value = "ca-toronto-1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "UK South (London)"
    value = "uk-london-1"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "Germany Central (Frankfurt)"
    value = "eu-frankfurt-1"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "India West (Mumbai)"
    value = "ap-mumbai-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Singapore"
    value = "ap-singapore-1"
    icon  = "/emojis/1f1f8-1f1ec.png"
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
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where workspace resources should be created. Leave empty to use tenancy_ocid."
  type        = string
  default     = ""
}

variable "tenancy_ocid" {
  description = "The tenancy OCID to use as the root compartment when compartment_ocid is empty."
  type        = string
  default     = ""
}

data "coder_parameter" "availability_domain_number" {
  name         = "availability_domain_number"
  display_name = "Availability domain"
  description  = "The 1-based availability domain number to use in the selected region."
  default      = 1
  type         = "number"
  mutable      = false

  validation {
    min = 1
    max = 3
  }
}

data "coder_parameter" "shape" {
  name         = "shape"
  display_name = "Shape"
  description  = "The OCI flexible VM shape to use for the workspace."
  default      = "VM.Standard.E4.Flex"
  mutable      = false

  option {
    name  = "AMD E4 Flex"
    value = "VM.Standard.E4.Flex"
  }
  option {
    name  = "AMD E5 Flex"
    value = "VM.Standard.E5.Flex"
  }
  option {
    name  = "Ampere A1 Flex"
    value = "VM.Standard.A1.Flex"
  }
}

data "coder_parameter" "ocpus" {
  name         = "ocpus"
  display_name = "OCPUs"
  description  = "The number of OCPUs to allocate to the flexible shape."
  default      = 1
  type         = "number"
  mutable      = false

  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory_in_gbs" {
  name         = "memory_in_gbs"
  display_name = "Memory"
  description  = "The amount of memory, in GiB, to allocate to the flexible shape."
  default      = 8
  type         = "number"
  mutable      = false

  validation {
    min = 1
    max = 128
  }
}

data "coder_parameter" "boot_volume_size_in_gbs" {
  name         = "boot_volume_size_in_gbs"
  display_name = "Boot volume size"
  description  = "The size of the instance boot volume in GiB."
  default      = 100
  type         = "number"
  mutable      = false

  validation {
    min = 50
    max = 32768
  }
}

provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "oci_identity_availability_domains" "available" {
  compartment_id = local.compartment_id
}

data "oci_core_images" "ubuntu" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = data.coder_parameter.shape.value
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

locals {
  compartment_id      = length(trimspace(var.compartment_ocid)) > 0 ? var.compartment_ocid : var.tenancy_ocid
  prefix              = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  linux_user          = "coder"
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[data.coder_parameter.availability_domain_number.value - 1].name
  desired_state       = data.coder_workspace.me.transition == "start" ? "RUNNING" : "STOPPED"
}

resource "coder_agent" "main" {
  arch = data.coder_parameter.shape.value == "VM.Standard.A1.Flex" ? "arm64" : "amd64"
  os   = "linux"
  auth = "token"

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

  agent_id = coder_agent.main.id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/${local.linux_user}"
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-config.yaml.tftpl", {
      hostname    = lower(data.coder_workspace.me.name)
      linux_user  = local.linux_user
      init_script = base64encode(coder_agent.main.init_script)
    })
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "${local.prefix}-vcn"
  dns_label      = "coder"

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = local.compartment_id
  display_name   = "${local.prefix}-igw"
  enabled        = true
  vcn_id         = oci_core_vcn.main.id

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_route_table" "main" {
  compartment_id = local.compartment_id
  display_name   = "${local.prefix}-route-table"
  vcn_id         = oci_core_vcn.main.id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_security_list" "main" {
  compartment_id = local.compartment_id
  display_name   = "${local.prefix}-security-list"
  vcn_id         = oci_core_vcn.main.id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_subnet" "main" {
  compartment_id             = local.compartment_id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "${local.prefix}-subnet"
  dns_label                  = "workspaces"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.main.id
  security_list_ids          = [oci_core_security_list.main.id]
  vcn_id                     = oci_core_vcn.main.id

  freeform_tags = {
    Coder_Provisioned = "true"
  }
}

resource "oci_core_instance" "main" {
  availability_domain = local.availability_domain
  compartment_id      = local.compartment_id
  display_name        = "${local.prefix}-instance"
  shape               = data.coder_parameter.shape.value
  state               = local.desired_state

  create_vnic_details {
    assign_public_ip = true
    display_name     = "${local.prefix}-vnic"
    hostname_label   = "workspace"
    subnet_id        = oci_core_subnet.main.id
  }

  metadata = {
    user_data = data.cloudinit_config.user_data.rendered
  }

  shape_config {
    memory_in_gbs = data.coder_parameter.memory_in_gbs.value
    ocpus         = data.coder_parameter.ocpus.value
  }

  source_details {
    boot_volume_size_in_gbs = data.coder_parameter.boot_volume_size_in_gbs.value
    source_id               = data.oci_core_images.ubuntu.images[0].id
    source_type             = "image"
  }

  freeform_tags = {
    Coder_Provisioned = "true"
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = oci_core_instance.main.id

  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "shape"
    value = oci_core_instance.main.shape
  }
  item {
    key   = "ocpus"
    value = tostring(data.coder_parameter.ocpus.value)
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory_in_gbs.value} GiB"
  }
  item {
    key   = "boot volume"
    value = "${data.coder_parameter.boot_volume_size_in_gbs.value} GiB"
  }
}
