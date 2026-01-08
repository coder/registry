---
display_name: VMware vSphere VM (Linux)
description: Provision VMware vSphere virtual machines as Coder workspaces
icon: ../../../../.icons/vsphere.svg
verified: false
tags: [vm, linux, vmware, vsphere]
---

# Summary

Provision VMware vSphere virtual machines as [Coder workspaces](https://coder.com/docs/workspaces) using this Terraform template.

## Prerequisites

To deploy Coder workspaces on VMware vSphere, you'll need the following:

### vSphere Resources

Before deploying, ensure your vSphere environment has:

- A **vSphere Datacenter** already created
- A **Compute Cluster** within that datacenter
- A **Datastore** with sufficient storage capacity
- A **Network** (port group) accessible by VMs
- A **VM Template** with Ubuntu and cloud-init configured

### VM Template Requirements

Your VM template must have

- **cloud-init** installed and configured for VMware datasource

### vSphere Authentication

You'll need the following credentials:

- **vSphere Server** (hostname or IP)
- **Username**
- **Password**
- **Datacenter Name**
- **Cluster Name**
- **Datastore Name**
- **Network Name**
- **VM Template Name**

[VMware Provider Documentation](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs)

---

## Example `.tfvars` File

```hcl
vsphere_server     = "vcenter.example.com"
vsphere_username   = "administrator@vsphere.local"
vsphere_password   = "YourSecurePassword123!"
vsphere_datacenter = "DC01"
cluster_name       = "Cluster01"
vsphere_datastore  = "datastore1"
vsphere_network    = "VM Network"
vm_template        = "ubuntu-22.04-cloud-init-template"
```

---

## Architecture

This template creates:

- A **vSphere Virtual Machine** per workspace
- **Dynamic resource allocation** (CPU, memory configurable by users)
- **Two disks**: root disk (from template) and separate home volume
- **Coder agent** installed via cloud-init
- **code-server** for browser-based VS Code access

## Workspace Parameters

Users can customize their workspace with:

- **VCPUs**: 1, 2, 4, or 8 virtual CPUs
- **Memory**: 1, 2, 4, 8, 16, or 32 GB RAM
- **Home Volume Size**: 10-1024 GB (default: 20 GB)
