# Oracle Cloud Infrastructure (OCI) Template for Coder
# This template provisions Coder workspaces on OCI Compute instances

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    oci = {
      source = "oracle/oci"
    }
  }
}

# OCI Provider Configuration
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  private_key_path = var.private_key_path
  fingerprint      = var.fingerprint
  region           = var.region
}

# Coder data
data "coder_workspace" "me" {}

# Variables
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key"
  type        = string
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "region" {
  description = "OCI Region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH Public Key"
  type        = string
}

variable "instance_shape" {
  description = "OCI Compute Instance Shape"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs"
  type        = number
  default     = 2
}

variable "instance_memory_in_gbs" {
  description = "Memory in GB"
  type        = number
  default     = 8
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get latest Oracle Linux image
data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Create VCN
resource "oci_core_vcn" "coder_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "coder-vcn-${data.coder_workspace.me.id}"
  dns_label      = "codervcn"
}

# Create Internet Gateway
resource "oci_core_internet_gateway" "coder_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn.id
  display_name   = "coder-igw-${data.coder_workspace.me.id}"
}

# Create Route Table
resource "oci_core_route_table" "coder_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn.id
  display_name   = "coder-rt-${data.coder_workspace.me.id}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.coder_igw.id
  }
}

# Create Security List
resource "oci_core_security_list" "coder_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coder_vcn.id
  display_name   = "coder-sl-${data.coder_workspace.me.id}"

  # SSH
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Coder app
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 3000
      max = 3000
    }
  }

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }
}

# Create Subnet
resource "oci_core_subnet" "coder_subnet" {
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.coder_vcn.id
  cidr_block          = "10.0.1.0/24"
  display_name        = "coder-subnet-${data.coder_workspace.me.id}"
  dns_label           = "codersubnet"
  security_list_ids   = [oci_core_security_list.coder_sl.id]
  route_table_id      = oci_core_route_table.coder_rt.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# Create Compute Instance
resource "oci_core_instance" "coder_instance" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${data.coder_workspace.me.name}"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.coder_subnet.id
    display_name     = "coder-vnic-${data.coder_workspace.me.id}"
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  preserve_boot_volume = false
}

# Coder Agent Resource
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<EOF
    #!/bin/bash
    
    # Install Coder agent
    curl -fsSL https://coder.com/install.sh | sh
    
    # Start Coder agent
    sudo systemctl enable --now coder
    
    # Install development tools
    sudo yum update -y
    sudo yum install -y git docker
    sudo systemctl enable --now docker
    
    # Add coder user to docker group
    sudo usermod -aG docker $USER
  EOF
}

# Outputs
output "instance_public_ip" {
  value       = oci_core_instance.coder_instance.public_ip
  description = "Public IP of the OCI instance"
}

output "instance_ocid" {
  value       = oci_core_instance.coder_instance.id
  description = "OCID of the OCI instance"
}
