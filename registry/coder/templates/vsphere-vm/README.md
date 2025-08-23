---
display_name: VMware vSphere VM
description: Provision VMware vSphere VMs as Coder workspaces with networking and datastore management
icon: ../../../../.icons/vmware.svg
verified: true
tags: [vm, linux, vsphere, vmware, on-premises, enterprise, persistent-vm]
---

# Remote Development on VMware vSphere VMs

Provision VMware vSphere Virtual Machines as [Coder workspaces](https://coder.com/docs/workspaces) with this enterprise-ready template. This template provides comprehensive vSphere integration with networking, datastore management, and VM lifecycle controls.

## Features

- **Full vSphere Integration**: Native support for vSphere infrastructure
- **Flexible Resource Configuration**: Configurable CPU, memory, and disk resources
- **Network Management**: Support for multiple networks and VLANs
- **Datastore Selection**: Choose from available datastores for VM placement
- **VM Folder Organization**: Optional VM folder placement for better organization
- **Snapshot Management**: Automatic snapshots on workspace stop
- **Hot-Add Support**: CPU and memory hot-add capabilities
- **Persistent Storage**: Optional additional data disks
- **Enterprise Security**: Integration with vSphere authentication and permissions
- **Development Mode**: Demo-friendly mode that works without actual vSphere infrastructure

## Development Mode vs Production Mode

This template supports two modes:

### Development Mode (Default)
- **Purpose**: Demo and testing without real vSphere infrastructure
- **Requirements**: None - works out of the box
- **Behavior**: Creates Coder agent with all apps, shows vSphere configuration UI
- **IP Address**: Returns `127.0.0.1 (demo)`
- **Use Case**: Demonstrations, training, template testing

### Production Mode
- **Purpose**: Real vSphere VM provisioning
- **Requirements**: Live vSphere environment and credentials
- **Behavior**: Creates actual VMs on vSphere infrastructure
- **Configuration**: Set `development_mode = false` in template

## Prerequisites

### For Development Mode
- No prerequisites - works immediately for demos

### For Production Mode (vSphere Environment)

- VMware vSphere 6.7 or later
- vCenter Server access
- VM template prepared with:
  - SSH server enabled
  - Cloud-init or VMware Tools installed
  - Network configuration (DHCP recommended)
  - Root/administrator access configured

### Authentication

Configure vSphere credentials as Terraform variables:

```bash
export TF_VAR_vsphere_server="vcenter.example.com"
export TF_VAR_vsphere_user="administrator@vsphere.local"
export TF_VAR_vsphere_password="your-password"
```

Or use a `.tfvars` file:

```hcl
vsphere_server   = "vcenter.example.com"
vsphere_user     = "administrator@vsphere.local"
vsphere_password = "your-secure-password"
```

### Required vSphere Permissions

The vSphere user needs the following permissions:

#### Datacenter Level
- `Datastore.AllocateSpace`
- `Datastore.Browse`
- `Network.Assign`

#### Cluster/Host Level
- `Host.Config.AdvancedConfig`
- `Host.Config.Resources`
- `Resource.AssignVMToPool`

#### VM Level
- `VirtualMachine.Config.AddExistingDisk`
- `VirtualMachine.Config.AddNewDisk`
- `VirtualMachine.Config.AddRemoveDevice`
- `VirtualMachine.Config.AdvancedConfig`
- `VirtualMachine.Config.Annotation`
- `VirtualMachine.Config.CPUCount`
- `VirtualMachine.Config.Memory`
- `VirtualMachine.Config.Settings`
- `VirtualMachine.Interact.PowerOff`
- `VirtualMachine.Interact.PowerOn`
- `VirtualMachine.Interact.Reset`
- `VirtualMachine.Inventory.Create`
- `VirtualMachine.Inventory.CreateFromExisting`
- `VirtualMachine.Inventory.Delete`
- `VirtualMachine.Provisioning.Clone`
- `VirtualMachine.Provisioning.Customize`
- `VirtualMachine.Provisioning.DeployTemplate`
- `VirtualMachine.State.CreateSnapshot`
- `VirtualMachine.State.RemoveSnapshot`

## Configuration Variables

### Required Variables

```hcl
variable "vsphere_server" {
  description = "vSphere server URL (e.g., vcenter.example.com)"
  type        = string
}

variable "vsphere_user" {
  description = "vSphere username"
  type        = string
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "datacenter_name" {
  description = "vSphere datacenter name"
  type        = string
}

variable "cluster_name" {
  description = "vSphere cluster name"
  type        = string
}

variable "default_datastore" {
  description = "Default datastore name"
  type        = string
}

variable "default_network" {
  description = "Default network name"
  type        = string
}

variable "vm_template" {
  description = "VM template name to clone from"
  type        = string
}

variable "development_mode" {
  description = "Enable development mode for demo purposes"
  type        = bool
  default     = true
}
```

### Example terraform.tfvars

```hcl
# vSphere Connection
vsphere_server   = "vcenter.company.com"
vsphere_user     = "coder-service@vsphere.local"
vsphere_password = "secure-password"

# Infrastructure
datacenter_name    = "Datacenter-01"
cluster_name      = "Cluster-01"
default_datastore = "datastore-ssd-01"
default_network   = "VM Network"
vm_template       = "ubuntu-20.04-template"
```

## User-Configurable Options

Users can customize their workspace with these parameters:

### CPU Configuration
- **2 vCPUs** (default)
- **4 vCPUs**
- **8 vCPUs**
- **16 vCPUs**

### Memory Configuration
- **2 GB** (2048 MB)
- **4 GB** (4096 MB) - default
- **8 GB** (8192 MB)
- **16 GB** (16384 MB)
- **32 GB** (32768 MB)

### Disk Size
- **50 GB** (default)
- **100 GB**
- **200 GB**
- **500 GB**

### Infrastructure Options
- **Datastore Selection**: Choose from available datastores
- **Network Selection**: Select appropriate network/VLAN
- **VM Folder**: Optional folder for VM organization

## Architecture

This template provisions the following resources:

### Core Resources
- **vSphere Virtual Machine**: Primary compute resource
- **Virtual Disks**: Root disk and optional data disk
- **Network Interface**: Connected to specified vSphere network
- **Snapshots**: Automatic snapshots on workspace lifecycle events

### Coder Integration
- **Coder Agent**: Installed automatically with startup script
- **Code Server**: Web-based VS Code interface
- **JetBrains Gateway**: Support for JetBrains IDEs
- **Monitoring**: CPU, memory, disk, and network metrics

### Security Features
- **VM Isolation**: Each workspace runs in isolated VM
- **Network Segmentation**: Configurable network placement
- **Snapshot Protection**: Automatic backup on stop
- **Access Control**: Integration with vSphere permissions

## VM Template Requirements

Your vSphere VM template should include:

### Base OS Configuration
```bash
# Ubuntu/Debian example preparation
sudo apt-get update
sudo apt-get install -y openssh-server cloud-init curl wget

# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh

# Configure SSH for key-based auth (recommended)
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh

# Install VMware Tools or open-vm-tools
sudo apt-get install -y open-vm-tools
```

### Network Configuration
```yaml
# /etc/netplan/01-netcfg.yaml (Ubuntu)
network:
  version: 2
  ethernets:
    ens192:  # Adjust interface name as needed
      dhcp4: true
      dhcp6: false
```

### Cloud-Init Configuration (Optional)
```yaml
# /etc/cloud/cloud.cfg.d/99-coder.cfg
datasource_list: [ VMware, OVF, None ]
disable_root: false
ssh_pwauth: true
```

## Usage Examples

### Basic Workspace Creation

1. **Configure Infrastructure Variables**:
   ```bash
   export TF_VAR_vsphere_server="vcenter.example.com"
   export TF_VAR_datacenter_name="DC1"
   export TF_VAR_cluster_name="Cluster1"
   export TF_VAR_vm_template="ubuntu-template"
   ```

2. **Deploy Template**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Access Workspace**:
   - Use Coder dashboard to access Code Server
   - Connect via JetBrains Gateway
   - SSH directly to the VM IP address

### Advanced Configuration

#### Multiple Networks
```hcl
# In main.tf, add additional network interfaces
network_interface {
  network_id   = data.vsphere_network.mgmt_network.id
  adapter_type = "vmxnet3"
}

network_interface {
  network_id   = data.vsphere_network.dev_network.id
  adapter_type = "vmxnet3"
}
```

#### Custom VM Specifications
```hcl
# Override default specifications
locals {
  custom_specs = {
    developer = {
      cpu    = 8
      memory = 16384
      disk   = 200
    }
    tester = {
      cpu    = 4
      memory = 8192
      disk   = 100
    }
  }
}
```

#### Storage Configuration
```hcl
# Additional data disk
disk {
  label            = "${local.vm_name}-data"
  size             = 500
  unit_number      = 1
  thin_provisioned = true
  datastore_id     = data.vsphere_datastore.ssd_datastore.id
}
```

## Monitoring and Maintenance

### Built-in Monitoring
- **CPU Usage**: Real-time CPU utilization
- **Memory Usage**: Memory consumption tracking
- **Disk Usage**: Disk space monitoring
- **Network Usage**: Network I/O statistics

### Maintenance Operations

#### VM Snapshots
```bash
# Manual snapshot creation
terraform apply -var="create_snapshot=true"

# Snapshot cleanup
terraform apply -var="cleanup_old_snapshots=true"
```

#### Resource Scaling
```bash
# Scale up resources (requires VM restart)
terraform apply -var="cpu_count=8" -var="memory_mb=16384"
```

## Troubleshooting

### Common Issues

#### VM Creation Fails
1. **Check vSphere Permissions**: Verify user has required permissions
2. **Template Availability**: Ensure VM template exists and is accessible
3. **Resource Availability**: Check datastore space and cluster resources
4. **Network Configuration**: Verify network exists and is accessible

#### Agent Connection Issues
1. **SSH Access**: Verify SSH is enabled on VM template
2. **Network Connectivity**: Check firewall rules and network configuration
3. **Agent Installation**: Review startup script logs in VM

#### Performance Issues
1. **Resource Allocation**: Increase CPU/memory allocation
2. **Storage Performance**: Use SSD datastores for better I/O
3. **Network Bandwidth**: Check network configuration and VLAN settings

### Debugging Commands

```bash
# Check VM status
terraform show | grep -A 10 "vsphere_virtual_machine"

# Verify vSphere connectivity
terraform console
> data.vsphere_datacenter.dc

# Review VM logs
ssh root@<vm-ip> "tail -f /var/log/cloud-init-output.log"
```

## Security Considerations

### Network Security
- Place VMs in appropriate network segments/VLANs
- Configure firewall rules for required ports only
- Use private networks where possible

### Access Control
- Implement least-privilege vSphere permissions
- Use service accounts for Terraform operations
- Enable audit logging in vSphere

### Data Protection
- Enable VM encryption if required
- Configure backup policies for VM snapshots
- Implement data retention policies

## Performance Optimization

### Resource Allocation
- Use memory reservations for consistent performance
- Enable CPU hot-add for dynamic scaling
- Configure appropriate disk types (thin vs thick provisioning)

### Storage Optimization
- Use SSD datastores for better I/O performance
- Consider vSAN for distributed storage
- Implement storage policies for different workload types

### Network Optimization
- Use VMXNET3 adapters for better performance
- Configure appropriate network bandwidth limits
- Consider SR-IOV for high-performance networking

## Integration Examples

### CI/CD Pipeline Integration
```yaml
# GitHub Actions example
- name: Deploy Coder Workspace
  uses: hashicorp/terraform-github-actions@v0.8.0
  with:
    tf_actions_version: 1.0.0
    tf_actions_subcommand: 'apply'
  env:
    TF_VAR_vsphere_server: ${{ secrets.VSPHERE_SERVER }}
    TF_VAR_vsphere_user: ${{ secrets.VSPHERE_USER }}
    TF_VAR_vsphere_password: ${{ secrets.VSPHERE_PASSWORD }}
```

### Monitoring Integration
```hcl
# Prometheus monitoring
resource "coder_app" "prometheus" {
  agent_id     = coder_agent.main[0].id
  display_name = "Prometheus"
  slug         = "prometheus"
  url          = "http://localhost:9090"
  icon         = "/icon/prometheus.svg"
}
```

## Support

For issues and questions:
- Review vSphere provider documentation: https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs
- Check Coder documentation: https://coder.com/docs
- Join the Coder community: https://discord.gg/coder

## Contributing

Contributions are welcome! Please:
1. Test changes in a development environment
2. Update documentation for new features
3. Follow Terraform best practices
4. Ensure compatibility with supported vSphere versions
