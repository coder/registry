---
display_name: VMware vSphere (Linux)
description: Provision VMware vSphere virtual machines as Coder workspaces
icon: ../../../../.icons/vsphere.svg
verified: false
tags: [vm, linux, vsphere, vmware, enterprise, on-premise]
---

# Remote Development on VMware vSphere VMs (Linux)

Provision VMware vSphere virtual machines as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### vSphere Infrastructure Requirements

- VMware vCenter Server (required for cloning VMs)
- A Linux VM template with:
  - VMware Tools installed
  - Cloud-init or open-vm-tools for guest customization
  - Network configured for DHCP (or static IP configuration)
- Sufficient resources in your cluster (CPU, memory, storage)

### Authentication

This template authenticates to vSphere using one of these methods:

1. **Environment Variables** (recommended):
   ```bash
   export VSPHERE_USER="administrator@vsphere.local"
   export VSPHERE_PASSWORD="your-password"
   export VSPHERE_SERVER="vcenter.example.com"
   ```

2. **Provider Configuration** - Edit the template to add credentials directly (not recommended for production)

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `vsphere_datacenter` | vSphere datacenter name | `DC1` |
| `vsphere_cluster` | Compute cluster name | `Cluster1` |
| `vsphere_datastore` | Datastore for VM storage | `datastore1` |
| `vsphere_network` | Network/portgroup name | `VM Network` |
| `vsphere_template` | Linux VM template name | `ubuntu-22.04-template` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `vsphere_folder` | VM folder path | `""` (root) |
| `allow_unverified_ssl` | Allow self-signed certs | `false` |
| `vm_domain` | VM domain name | `local` |
| `vm_dns_servers` | DNS servers | `["8.8.8.8", "8.8.4.4"]` |
| `vm_ipv4_gateway` | Static IP gateway | `""` (DHCP) |

## Required Permissions

The vSphere user needs the following permissions:

### Virtual Machine Permissions
- `VirtualMachine.Interact.PowerOn`
- `VirtualMachine.Interact.PowerOff`
- `VirtualMachine.Interact.Reset`
- `VirtualMachine.Inventory.Create`
- `VirtualMachine.Inventory.Delete`
- `VirtualMachine.Config.*`
- `VirtualMachine.Provisioning.Clone`
- `VirtualMachine.Provisioning.DeployTemplate`
- `VirtualMachine.Provisioning.Customize`

### Datastore Permissions
- `Datastore.AllocateSpace`
- `Datastore.Browse`
- `Datastore.FileManagement`

### Network Permissions
- `Network.Assign`

### Resource Permissions
- `Resource.AssignVMToPool`

## Creating a VM Template

### Ubuntu 22.04 Template Example

1. Create a new VM with Ubuntu 22.04 Server ISO
2. Install the OS with minimal configuration
3. Install required packages:
   ```bash
   sudo apt update
   sudo apt install -y open-vm-tools cloud-init curl
   ```
4. Create the coder user:
   ```bash
   sudo useradd -m -s /bin/bash coder
   sudo usermod -aG sudo coder
   echo "coder ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/coder
   ```
5. Clean up and prepare for templating:
   ```bash
   sudo cloud-init clean
   sudo rm -rf /var/lib/cloud/instances/*
   sudo truncate -s 0 /etc/machine-id
   ```
6. Shut down the VM and convert to template

## Architecture

This template provisions the following resources:

- VMware Virtual Machine (cloned from template)
- Guest customization via cloud-init
- Network interface with DHCP or static IP

The VM is fully persistent - the filesystem is preserved across workspace restarts.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template for your specific vSphere environment.

## code-server

`code-server` is installed via the Coder agent using the code-server module.
Access it through the Coder dashboard UI.

## Customization Tips

### Using a Specific Folder

Set `vsphere_folder` to organize VMs:
```hcl
vsphere_folder = "Coder/Workspaces"
```

### Static IP Configuration

For environments without DHCP, modify the network_interface block in the customize section:
```hcl
network_interface {
  ipv4_address = "192.168.1.100"
  ipv4_netmask = 24
}
```

### Using a Datastore Cluster

Replace `vsphere_datastore` with `vsphere_datastore_cluster` data source for DRS-enabled storage.

### Adding Additional Disks

Add more `disk` blocks to attach additional storage to the VM.
