---
display_name: Proxmox VE (Virtual Machine)
description: Provision Proxmox VE VMs as Coder workspaces
icon: ../../../../.icons/proxmox.svg
maintainer_github: coder
verified: true
tags: [vm, linux, proxmox, qemu, kvm]
---

# Remote Development on Proxmox VE VMs

Provision Proxmox VE virtual machines as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### Infrastructure

**Proxmox VE Cluster**: This template requires an existing Proxmox VE cluster (version 7.0 or higher recommended).

**VM Template**: This template uses cloud-init enabled VM templates. You'll need to create a template with:
- Ubuntu 22.04 LTS (or your preferred Linux distribution)
- Cloud-init package installed
- Qemu Guest Agent installed

**Network**: Ensure your Proxmox VE cluster has proper network configuration with DHCP or static IP assignment.

### Authentication

This template authenticates to Proxmox VE using API tokens. You'll need to:

1. Create a user in Proxmox VE for Coder:
   ```bash
   pveum user add coder@pve
   ```

2. Create an API token:
   ```bash
   pveum user token add coder@pve coder-token --privsep=0
   ```

3. Assign appropriate permissions:
   ```bash
   pveum role add CoderRole -privs "VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.Monitor,VM.PowerMgmt,VM.Snapshot,VM.Snapshot.Rollback,Datastore.Allocate,Datastore.AllocateSpace,Datastore.Audit,SDN.Use"
   pveum aclmod / -user coder@pve -role CoderRole
   ```

4. Set the following environment variables when running Coder:
   ```bash
   export PM_API_URL="https://your-proxmox-host:8006/api2/json"
   export PM_API_TOKEN_ID="coder@pve!coder-token"
   export PM_API_TOKEN_SECRET="your-api-token-secret"
   ```

### Creating a VM Template

1. Create a new VM in Proxmox VE
2. Install Ubuntu 22.04 LTS with cloud-init and qemu-guest-agent
3. Install development tools and configure the system
4. Shut down the VM and convert it to a template:
   ```bash
   qm template <vm-id>
   ```

## Architecture

This template provisions the following resources:

- Proxmox VE VM (persistent, based on template)
- Cloud-init configuration for automated setup
- Network interface with DHCP or static IP
- Virtual disk storage

The VM is persistent, meaning the full filesystem is preserved when the workspace restarts. The template uses cloud-init for initial configuration and the Qemu Guest Agent for better integration.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.

## Features

- **Resource Configuration**: Configurable CPU cores, memory, and disk size
- **Template-based**: Fast deployment using Proxmox VE VM templates
- **Cloud-init**: Automated initial configuration
- **Network Integration**: Automatic network configuration
- **Storage Flexibility**: Support for different storage backends
- **Agent Integration**: Full Coder agent support with metadata

## Customization

You can customize this template by:

- Modifying VM resource parameters
- Changing the base template
- Adjusting network configuration
- Adding additional storage devices
- Configuring backup schedules

## Troubleshooting

- Ensure the Proxmox VE API is accessible from your Coder deployment
- Verify API token permissions are correctly configured
- Check that the VM template exists and has cloud-init enabled
- Ensure sufficient resources are available on the target node
