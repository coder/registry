---
display_name: Oracle Cloud Infrastructure (Linux)
description: Provision OCI Compute instances as Coder workspaces
icon: ../../../../.icons/oci.svg
verified: true
tags: [vm, linux, oci, oracle, persistent-vm, cloud]
---

# Remote Development on Oracle Cloud Infrastructure (Linux)

Provision Oracle Cloud Infrastructure (OCI) Compute instances as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### Authentication

This template authenticates to OCI using the provider's default [authentication methods](https://registry.terraform.io/providers/oracle/oci/latest/docs#authentication).

You can authenticate using:

1. **API Key Authentication** (Recommended for local development):
   - Create an API key in OCI Console
   - Configure `~/.oci/config` file with your credentials
   - Example config:
     ```ini
     [DEFAULT]
     user=ocid1.user.oc1..aaaaaaaa...
     fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
     tenancy=ocid1.tenancy.oc1..aaaaaaaa...
     region=us-ashburn-1
     key_file=~/.oci/oci_api_key.pem
     ```

2. **Instance Principal Authentication** (Recommended for production):
   - Use when running Coder on an OCI compute instance
   - Configure dynamic group and policies
   - Set `auth = "InstancePrincipal"` in the provider block

3. **Environment Variables**:
   - `TF_VAR_tenancy_ocid`
   - `TF_VAR_user_ocid`
   - `TF_VAR_fingerprint`
   - `TF_VAR_private_key_path`
   - `TF_VAR_region`

### Required OCI Resources

Before using this template, you need to create:

1. **Compartment**: A compartment to organize your resources
2. **VCN (Virtual Cloud Network)**: A virtual network for your instances
3. **Subnet**: A subnet within your VCN with internet access
4. **Security List/NSG**: Allow SSH (port 22) and Coder agent traffic

### Required Variables

You must provide the following variables when creating a workspace:

- `compartment_ocid`: The OCID of your OCI compartment
- `subnet_ocid`: The OCID of your subnet
- `ssh_public_key`: Your SSH public key for instance access

## Required Permissions / Policies

The following IAM policy allows Coder to manage compute instances:

```
Allow group CoderUsers to manage instance-family in compartment <compartment-name>
Allow group CoderUsers to use virtual-network-family in compartment <compartment-name>
Allow group CoderUsers to read app-catalog-listing in compartment <compartment-name>
```

For more granular permissions:

```
Allow group CoderUsers to manage instances in compartment <compartment-name>
Allow group CoderUsers to manage instance-configurations in compartment <compartment-name>
Allow group CoderUsers to manage instance-pools in compartment <compartment-name>
Allow group CoderUsers to manage volume-attachments in compartment <compartment-name>
Allow group CoderUsers to manage volumes in compartment <compartment-name>
Allow group CoderUsers to use subnets in compartment <compartment-name>
Allow group CoderUsers to use vnics in compartment <compartment-name>
Allow group CoderUsers to use network-security-groups in compartment <compartment-name>
```

## Architecture

This template provisions the following resources:

- **OCI Compute Instance**: Ubuntu 22.04 LTS virtual machine
- **Boot Volume**: Persistent storage for the instance
- **VNIC**: Virtual network interface with public IP
- **Cloud-init Configuration**: Automated instance setup

The template uses `oci_core_instance_action` to start and stop the VM, making it fully persistent. The entire filesystem is preserved when the workspace restarts.

### Instance Shapes

The template supports various instance shapes:

- **VM.Standard.E2.1.Micro**: Always Free tier (1 OCPU, 1 GB RAM)
- **VM.Standard.A1.Flex**: Ampere ARM-based (flexible OCPU/memory)
- **VM.Standard.E4.Flex**: AMD-based flexible shape
- **VM.Standard.E3.Flex**: Intel-based flexible shape

## Features

- ✅ **Always Free Tier Support**: Use OCI's generous free tier
- ✅ **Multi-Region**: Deploy in any OCI region worldwide
- ✅ **Persistent Storage**: Full filesystem persistence across restarts
- ✅ **Flexible Shapes**: Choose from various compute shapes
- ✅ **Code Server**: Pre-configured VS Code in the browser
- ✅ **JetBrains Gateway**: Support for JetBrains IDEs
- ✅ **Cloud-init**: Automated instance configuration
- ✅ **Resource Monitoring**: CPU, memory, and disk usage tracking

## Usage

1. **Set up OCI credentials** as described in the Prerequisites section

2. **Create required OCI resources**:
   - Compartment
   - VCN with internet gateway
   - Subnet with route to internet gateway
   - Security list allowing inbound SSH

3. **Create a workspace** in Coder:
   - Select your preferred region
   - Choose an instance shape
   - Provide compartment OCID, subnet OCID, and SSH public key

4. **Access your workspace**:
   - Use Code Server through the browser
   - Connect via JetBrains Gateway
   - SSH directly to the instance

## Variables

| Name              | Description                                      | Type     | Default                | Required |
| ----------------- | ------------------------------------------------ | -------- | ---------------------- | -------- |
| region            | OCI region to deploy the workspace               | `string` | `"us-ashburn-1"`       | no       |
| instance_shape    | OCI compute shape for the instance               | `string` | `"VM.Standard.E2.1.Micro"` | no   |
| compartment_ocid  | OCID of the compartment for resources            | `string` | -                      | yes      |
| subnet_ocid       | OCID of the subnet for the instance              | `string` | -                      | yes      |
| ssh_public_key    | SSH public key for instance access               | `string` | -                      | yes      |

## Resources Created

- **oci_core_instance**: The compute instance running Ubuntu 22.04
- **oci_core_instance_action**: Manages instance start/stop state
- **coder_agent**: Coder agent for workspace connectivity
- **coder_metadata**: Workspace information display

## Customization

### Modify the Startup Script

Edit the `startup_script` in the `coder_agent` resource to add custom initialization:

```hcl
startup_script = <<-EOT
  set -e
  
  # Install additional tools
  sudo apt-get install -y docker.io
  sudo usermod -aG docker ubuntu
  
  # Clone repositories
  git clone https://github.com/your-org/your-repo.git
EOT
```

### Change Instance Shape

Modify the `instance_shape` parameter options to include different shapes:

```hcl
option {
  name  = "8 OCPU, 64 GB RAM"
  value = "VM.Standard.E4.Flex"
}
```

### Add Additional Storage

Add a block volume for extra storage:

```hcl
resource "oci_core_volume" "data" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${data.coder_workspace.me.name}-data"
  size_in_gbs         = 100
}

resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.dev.id
  volume_id       = oci_core_volume.data.id
}
```

## Troubleshooting

### Common Issues

**Issue**: "Service error: NotAuthorizedOrNotFound"
- **Solution**: Verify your IAM policies allow the required permissions
- Check that the compartment OCID is correct

**Issue**: "Out of capacity for shape VM.Standard.E2.1.Micro"
- **Solution**: Try a different availability domain or region
- Use a different instance shape

**Issue**: "Subnet not found"
- **Solution**: Verify the subnet OCID is correct
- Ensure the subnet is in the same region as specified

**Issue**: "Instance fails to start"
- **Solution**: Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
- Verify security list allows required traffic

**Issue**: "Cannot connect to workspace"
- **Solution**: Ensure security list allows inbound traffic on Coder agent port
- Verify the instance has a public IP address
- Check that the Coder agent is running: `systemctl status coder-agent`

### Getting OCIDs

To find your OCIDs:

1. **Compartment OCID**: OCI Console → Identity → Compartments
2. **Subnet OCID**: OCI Console → Networking → Virtual Cloud Networks → Select VCN → Subnets
3. **Tenancy OCID**: OCI Console → Profile → Tenancy

### Networking Setup

For a basic setup, create:

1. **VCN** with CIDR 10.0.0.0/16
2. **Internet Gateway** attached to VCN
3. **Route Table** with route to internet gateway (0.0.0.0/0)
4. **Security List** with rules:
   - Ingress: TCP port 22 (SSH) from 0.0.0.0/0
   - Ingress: TCP ports for Coder agent
   - Egress: All traffic to 0.0.0.0/0
5. **Subnet** using the route table and security list

## OCI Free Tier

Oracle Cloud offers a generous Always Free tier:

- **2 AMD-based Compute VMs** (VM.Standard.E2.1.Micro)
- **4 Arm-based Ampere A1 cores** and 24 GB memory (VM.Standard.A1.Flex)
- **200 GB total Block Volume storage**
- **10 TB outbound data transfer per month**

This template is configured to use the Always Free tier by default.

## Contributing

Contributions are welcome! Please see the [contributing guidelines](../../../../CONTRIBUTING.md) for more information.

## References

- [OCI Terraform Provider Documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [OCI Compute Documentation](https://docs.oracle.com/en-us/iaas/Content/Compute/home.htm)
- [OCI Free Tier](https://www.oracle.com/cloud/free/)
- [Coder Documentation](https://coder.com/docs)
