---
display_name: "Proxmox Linux"
description: "Develop in Linux on a Proxmox VM"
icon: "../../../../.icons/desktop.svg"
verified: false
tags: ["linux", "proxmox", "vm", "qemu", "kvm"]
---

# Proxmox Linux

This template provisions a Linux development environment on Proxmox Virtual Environment using QEMU/KVM virtualization.

## Features

- **Flexible VM Configuration**: Choose CPU cores (2-8), memory (2-16 GB), and disk size (32-256 GB)
- **Multiple Linux Distributions**: Support for Ubuntu 22.04/20.04 and Debian 12 cloud images
- **Storage Options**: Compatible with local-lvm, local-zfs, and NFS storage backends
- **Network Configuration**: Configurable network bridges (vmbr0, vmbr1)
- **Cloud-init Integration**: Automated VM provisioning with user account setup
- **Development Tools**: Pre-configured with code-server and JetBrains Gateway
- **Resource Monitoring**: Built-in CPU, memory, and disk usage metrics

## Prerequisites

### Proxmox VE Setup
- Proxmox VE 8.x cluster with API access
- VM templates with cloud-init support:
  - `ubuntu-22.04-cloudinit` - Ubuntu 22.04 LTS cloud image
  - `ubuntu-20.04-cloudinit` - Ubuntu 20.04 LTS cloud image
  - `debian-12-cloudinit` - Debian 12 cloud image

### Authentication
Configure Proxmox provider authentication using one of:

**API Token (Recommended)**:
```bash
export PROXMOX_VE_ENDPOINT="https://your-proxmox.example.com:8006"
export PROXMOX_VE_API_TOKEN="user@realm!tokenid=token-secret"
export PROXMOX_VE_INSECURE=true  # if using self-signed certificates
```

**Username/Password**:
```bash
export PROXMOX_VE_ENDPOINT="https://your-proxmox.example.com:8006"
export PROXMOX_VE_USERNAME="root@pam"
export PROXMOX_VE_PASSWORD="your-password"
export PROXMOX_VE_INSECURE=true
```

### Creating VM Templates

To create cloud-init compatible templates:

1. Download cloud images:
```bash
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

2. Create VM template:
```bash
qm create 9000 --name ubuntu-22.04-cloudinit --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

## Architecture

The template creates:

1. **Proxmox VM**: QEMU/KVM virtual machine with specified resources
2. **Cloud-init Configuration**: Automated setup with user accounts and SSH keys
3. **Coder Agent**: Installed and configured for workspace connectivity
4. **Development Environment**: code-server and JetBrains Gateway pre-configured

## Network Configuration

VMs are configured with:
- DHCP networking by default
- Configurable network bridge selection
- QEMU guest agent for IP address detection
- SSH access via Coder agent tunnel

## Storage Management

- **Primary Disk**: Configurable size with virtio interface for performance
- **Cloud-init Disk**: Separate IDE interface for initialization data
- **Storage Backend**: Support for LVM, ZFS, and NFS datastores
- **Disk Optimization**: SSD emulation, discard support, and iothread enabled

## Security Features

- **Isolated VMs**: Each workspace runs in its own virtual machine
- **SSH Key Authentication**: Automatic SSH key injection via cloud-init
- **Network Isolation**: VMs can be placed on separate network bridges
- **Resource Limits**: CPU and memory limits prevent resource exhaustion

## Monitoring

Built-in resource monitoring includes:
- CPU usage percentage
- Memory utilization
- Disk space usage
- VM status and metadata

## Customization

Template parameters allow customization of:
- Proxmox node selection
- VM template/image selection
- CPU core count (2-8 cores)
- Memory allocation (2-16 GB)
- Disk size (32-256 GB)
- Storage datastore selection
- Network bridge configuration

## Troubleshooting

### VM Creation Issues
- Verify VM template exists and has cloud-init configured
- Check datastore has sufficient space
- Ensure network bridge exists on selected node

### Agent Connection Problems
- Verify QEMU guest agent is installed in VM template
- Check cloud-init configuration is applied correctly
- Ensure SSH keys are properly injected

### Performance Optimization
- Use SSD-backed storage for better I/O performance
- Enable virtio drivers for network and disk interfaces
- Allocate sufficient memory to avoid swapping


