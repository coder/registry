---
display_name: VMware vSphere VM (Linux)
description: Provision VMware vSphere VMs with networking and datastore management
icon: ../../../../.icons/box-emoji.svg
maintainer_github: coder
verified: true
tags: [vm, linux, vsphere, vmware, enterprise, on-premises, persistent-vm]
---

# Remote Development on VMware vSphere VMs (Linux)

Provision VMware vSphere VMs as [Coder workspaces](https://coder.com/docs/workspaces) with this enterprise-ready template. This template provides comprehensive VM configuration, networking setup, and datastore management for on-premises deployments.

## Prerequisites

### vSphere Environment

- VMware vSphere 6.7 or later
- vCenter Server access
- At least one ESXi host in a cluster
- A VM template with Linux OS (Ubuntu 20.04+ recommended)
- Network connectivity between Coder server and vSphere environment

### Authentication

This template authenticates to vSphere using the provider's [authentication methods](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs#authentication). The recommended approach is via environment variables:

```bash
export VSPHERE_USER="your-username@vsphere.local"
export VSPHERE_PASSWORD="your-password"
export VSPHERE_SERVER="vcenter.company.com"
export VSPHERE_ALLOW_UNVERIFIED_SSL="true"  # Only for testing
```

Alternatively, configure the provider directly in the template or use a `.terraformrc` file.

### Required vSphere Permissions

The user account needs the following minimum permissions on the relevant vSphere objects:

#### Datacenter Level
- **Virtual Machine > Configuration > All**
- **Virtual Machine > Interaction > All**
- **Virtual Machine > Inventory > All**
- **Virtual Machine > Provisioning > All**

#### Datastore Level
- **Datastore > Allocate space**
- **Datastore > Browse datastore**
- **Datastore > Low level file operations**

#### Network Level
- **Network > Assign network**

#### Resource Pool/Cluster Level
- **Resource > Assign virtual machine to resource pool**

## Configuration Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `vsphere_server` | vSphere server hostname or IP | - | ✓ |
| `datacenter` | vSphere datacenter name | `datacenter1` | ✓ |
| `cluster` | vSphere cluster name | `cluster1` | ✓ |
| `datastore` | Datastore for VM storage | - | ✓ |
| `network` | Network/port group name | `VM Network` | ✓ |
| `template_name` | VM template to clone from | - | ✓ |
| `cpu_count` | Number of virtual CPUs | `2` | - |
| `memory` | Memory in MB | `4096` | - |
| `disk_size` | Primary disk size in GB | `50` | - |

## Architecture

This template provisions the following resources:

### Infrastructure Components
- **VMware vSphere Virtual Machine** - Primary compute resource
- **Virtual Network Interface** - Connected to specified port group
- **Virtual Disk** - Thin-provisioned storage on specified datastore
- **Resource Pool Assignment** - VM assigned to cluster resource pool

### Coder Integration
- **Coder Agent** - Installed automatically via SSH provisioner
- **Code Server** - Web-based VS Code interface
- **JetBrains Gateway** - Support for JetBrains IDEs
- **Workspace Metadata** - VM details displayed in Coder dashboard

### Network Configuration

The template supports various vSphere networking configurations:

- **Standard vSwitches** - Traditional port groups
- **Distributed vSwitches** - Enterprise networking with advanced features
- **NSX Networks** - Software-defined networking integration
- **DHCP or Static IP** - Configurable via guest customization

### Datastore Management

Supports multiple datastore types:
- **VMFS** - Traditional vSphere datastores
- **NFS** - Network-attached storage
- **vSAN** - Software-defined storage
- **Datastore Clusters** - Storage DRS for automated placement

## VM Template Requirements

Your vSphere VM template should meet these requirements:

### Operating System
- Ubuntu 20.04 LTS or later (recommended)
- CentOS 8+ or RHEL 8+
- Other Linux distributions with SSH and cloud-init support

### Required Software
- **SSH server** - For Coder agent installation
- **Cloud-init** (recommended) - For guest customization
- **VMware Tools** - For better guest integration
- **sudo access** - For the default user account

### User Account
Create a user account (e.g., `coder`) with:
- sudo privileges without password prompt
- SSH key-based authentication (optional but recommended)
- Home directory with appropriate permissions

### Example cloud-init Configuration
```yaml
#cloud-config
users:
  - name: coder
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo, docker
    home: /home/coder
    
packages:
  - curl
  - wget
  - git
  - vim
  - htop
  - docker.io
  
runcmd:
  - systemctl enable docker
  - usermod -aG docker coder
```

## Security Considerations

### Network Security
- Ensure proper firewall rules between Coder server and vSphere environment
- Use VPNs or private networks for sensitive environments
- Configure network segmentation for workspace isolation

### Access Control
- Use dedicated service accounts with minimal required permissions
- Implement vSphere role-based access control (RBAC)
- Enable audit logging for vSphere operations

### VM Security
- Keep VM templates updated with latest security patches
- Use encrypted datastores for sensitive workloads
- Implement guest-level security controls

## Customization Examples

### Custom VM Specifications
```hcl
# Add to data "coder_parameter" blocks for custom sizing
data "coder_parameter" "custom_cpu" {
  name         = "cpu_count"
  display_name = "CPU Count"
  default      = "4"
  option {
    name  = "High Performance (16 vCPUs)"
    value = "16"
  }
}
```

### Multiple Network Interfaces
```hcl
# Add additional network interfaces
network_interface {
  network_id   = data.vsphere_network.management.id
  adapter_type = "vmxnet3"
}

network_interface {
  network_id   = data.vsphere_network.storage.id
  adapter_type = "vmxnet3"
}
```

### Additional Datastores
```hcl
# Add data disk on different datastore
disk {
  label            = "data-disk"
  size             = 500
  thin_provisioned = true
  unit_number      = 1
  datastore_id     = data.vsphere_datastore.fast_storage.id
}
```

### GPU Passthrough
```hcl
# Enable GPU for AI/ML workloads
resource "vsphere_virtual_machine" "vm" {
  # ... other configuration ...
  
  pci_device_id = [data.vsphere_pci_device.gpu.id]
  memory_reservation = tonumber(data.coder_parameter.memory.value)
}
```

## Troubleshooting

### Common Issues

#### 1. Template Clone Failures
```
Error: error cloning virtual machine: The operation is not supported on the object
```
**Solution**: Ensure the VM template is properly configured and not powered on.

#### 2. Network Configuration Issues
```
Error: network interface not found
```
**Solution**: Verify the network/port group name exists in the specified datacenter.

#### 3. Insufficient Permissions
```
Error: permission denied
```
**Solution**: Review and assign the required vSphere permissions listed above.

#### 4. Agent Connection Timeouts
```
Error: timeout waiting for agent to connect
```
**Solution**: 
- Check SSH connectivity between Coder and the VM
- Verify firewall rules allow traffic on required ports
- Ensure the VM template has SSH server enabled

### Debugging Steps

1. **Verify vSphere Connectivity**
   ```bash
   # Test vSphere API access
   curl -k "https://$VSPHERE_SERVER/rest/com/vmware/cis/session" \
     -X POST -u "$VSPHERE_USER:$VSPHERE_PASSWORD"
   ```

2. **Check VM Power State**
   - Verify VMs power on/off correctly based on workspace state
   - Check vSphere events for error messages

3. **Network Troubleshooting**
   - Ping test between Coder server and VM
   - Verify DNS resolution if using hostnames
   - Check vSphere port group configuration

4. **Agent Logs**
   ```bash
   # On the VM, check Coder agent logs
   journalctl -u coder-agent -f
   ```

## Performance Optimization

### Resource Allocation
- Enable CPU and memory hot-add for dynamic scaling
- Use thin-provisioned disks to optimize storage utilization
- Configure appropriate CPU/memory reservations for guaranteed resources

### Storage Performance
- Use SSD-backed datastores for better I/O performance
- Enable Storage DRS for automatic load balancing
- Consider vSAN for software-defined storage benefits

### Network Performance
- Use VMXNET3 network adapters for best performance
- Configure distributed vSwitches for advanced networking features
- Implement network I/O control for bandwidth management

## Integration Examples

### CI/CD Integration
This template works well with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
name: Deploy Development Environment
on:
  push:
    branches: [develop]
    
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Create Coder Workspace
        run: |
          coder create --template=vsphere-linux \
            --parameter datacenter=prod-dc \
            --parameter cluster=dev-cluster \
            --parameter datastore=dev-storage \
            dev-${{ github.sha }}
```

### Monitoring Integration
```hcl
# Add monitoring agent to startup script
resource "coder_agent" "dev" {
  startup_script = <<-EOT
    # Install monitoring agent
    curl -sSL https://monitoring.company.com/install.sh | bash
    
    # Configure workspace-specific monitoring
    echo "workspace.name=${data.coder_workspace.me.name}" >> /etc/monitoring/config
  EOT
}
```

## Best Practices

1. **Template Management**
   - Regularly update VM templates with security patches
   - Use automation tools like Packer for template creation
   - Maintain separate templates for different use cases

2. **Resource Management**
   - Set appropriate resource limits to prevent over-allocation
   - Use resource pools to organize and limit workspace resources
   - Monitor resource utilization across workspaces

3. **Backup and Recovery**
   - Implement regular VM snapshots for data protection
   - Use vSphere backup solutions for workspace data
   - Document recovery procedures

4. **Cost Optimization**
   - Automatically power off idle workspaces
   - Use thin provisioning to optimize storage usage
   - Implement resource quotas and governance policies

## Support

For issues specific to this template:
- Check the [Coder documentation](https://coder.com/docs)
- Visit [Coder Community](https://github.com/coder/coder/discussions)
- Review [vSphere provider documentation](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs)

For vSphere-specific issues:
- Consult VMware documentation
- Contact your vSphere administrator
- Check VMware support resources