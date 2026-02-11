# Oracle Cloud Infrastructure (OCI) Template for Coder

This template allows you to provision Coder workspaces on Oracle Cloud Infrastructure (OCI) Compute instances.

## Overview

Deploy Coder workspaces on OCI with customizable compute shapes, networking, and automatic Coder agent setup.

## Features

- ✅ OCI Compute instance provisioning
- ✅ Customizable instance shapes (OCPUs and Memory)
- ✅ Automatic VCN, subnet, and security group creation
- ✅ Coder agent auto-installation
- ✅ SSH access enabled

## Prerequisites

1. **OCI Account** with necessary permissions
2. **OCI API Key** configured
3. **Terraform** >= 1.0 installed

## Configuration

### 1. OCI API Key Setup

Follow the [OCI documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm) to create an API signing key.

### 2. Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `tenancy_ocid` | Your OCI Tenancy OCID | `ocid1.tenancy.oc1..xxx` |
| `user_ocid` | Your OCI User OCID | `ocid1.user.oc1..xxx` |
| `private_key_path` | Path to your API private key | `~/.oci/oci_api_key.pem` |
| `fingerprint` | API Key fingerprint | `xx:xx:xx:xx:xx:xx` |
| `region` | OCI Region | `us-ashburn-1` |
| `compartment_ocid` | Compartment OCID | `ocid1.compartment.oc1..xxx` |
| `ssh_public_key` | Your SSH public key | `ssh-rsa AAA...` |

### 3. Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `instance_shape` | Compute shape | `VM.Standard.E4.Flex` |
| `instance_ocpus` | Number of OCPUs | `2` |
| `instance_memory_in_gbs` | Memory in GB | `8` |

## Usage

### As a Coder Template

```bash
# Login to Coder
coder login https://coder.example.com

# Create template from this directory
coder templates create oci-template

# Create a workspace
coder create oci-workspace --template oci-template
```

### With Terraform Directly

```bash
# Set environment variables
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..xxx"
export TF_VAR_user_ocid="ocid1.user.oc1..xxx"
export TF_VAR_private_key_path="~/.oci/oci_api_key.pem"
export TF_VAR_fingerprint="xx:xx:xx:xx:xx:xx"
export TF_VAR_compartment_ocid="ocid1.compartment.oc1..xxx"
export TF_VAR_ssh_public_key="ssh-rsa AAA..."

# Initialize and apply
terraform init
terraform apply
```

## Architecture

```
┌─────────────────────────────────────┐
│           OCI Region                │
│  ┌───────────────────────────────┐  │
│  │           VCN                 │  │
│  │  CIDR: 10.0.0.0/16           │  │
│  │                               │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │      Subnet             │  │  │
│  │  │  CIDR: 10.0.1.0/24     │  │  │
│  │  │                         │  │  │
│  │  │  ┌─────────────────┐    │  │  │
│  │  │  │  Compute        │    │  │  │
│  │  │  │  Instance       │    │  │  │
│  │  │  │                 │    │  │  │
│  │  │  │  - Coder Agent  │    │  │  │
│  │  │  │  - Docker       │    │  │  │
│  │  │  │  - Dev Tools    │    │  │  │
│  │  │  └─────────────────┘    │  │  │
│  │  └─────────────────────────┘  │  │
│  │                               │  │
│  │  Internet Gateway             │  │
│  │  Route Table                  │  │
│  │  Security List                │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Compute Shapes

Common OCI compute shapes supported:

| Shape | OCPUs | Memory | Use Case |
|-------|-------|--------|----------|
| VM.Standard.E4.Flex | 1-64 | 1-1024 GB | General purpose |
| VM.Standard.A1.Flex | 1-80 | 1-512 GB | Arm-based, cost-effective |
| VM.Standard3.Flex | 1-32 | 1-512 GB | Intel Xeon |

## Networking

The template creates:
- **VCN** with CIDR `10.0.0.0/16`
- **Subnet** with CIDR `10.0.1.0/24`
- **Internet Gateway** for outbound connectivity
- **Security List** allowing:
  - SSH (port 22)
  - Coder app (port 3000)

## Security

- SSH key authentication required
- Security groups restrict inbound traffic
- No password authentication
- Boot volume not preserved on termination

## Cost Considerations

- OCI offers [Always Free](https://www.oracle.com/cloud/free/) tier resources
- VM.Standard.E4.Flex with 1 OCPU and 1 GB RAM is Always Free eligible
- Monitor your usage to avoid unexpected charges

## Troubleshooting

### Instance Not Creating

Check OCI console for:
- Service limits in your region
- Available capacity in availability domain
- Valid compartment permissions

### Cannot Connect via SSH

1. Verify SSH key is correct
2. Check security list allows port 22
3. Ensure instance has public IP assigned

### Coder Agent Not Starting

1. Check instance has internet access
2. Verify startup script logs: `/var/log/messages`
3. Ensure correct architecture (amd64/arm64)

## Resources Created

| Resource | Type | Description |
|----------|------|-------------|
| `oci_core_vcn` | Networking | Virtual Cloud Network |
| `oci_core_subnet` | Networking | Subnet for instances |
| `oci_core_internet_gateway` | Networking | Internet access |
| `oci_core_security_list` | Networking | Firewall rules |
| `oci_core_instance` | Compute | Coder workspace VM |
| `coder_agent` | Coder | Coder agent resource |

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Or via Coder UI
coder delete oci-workspace
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a PR with your changes
4. Include testing notes

## License

MIT License - See LICENSE file

## References

- [OCI Documentation](https://docs.oracle.com/en-us/iaas/Content/home.htm)
- [Coder Documentation](https://coder.com/docs)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)

## Support

For issues related to:
- **OCI**: Contact Oracle Cloud Support
- **Coder**: Visit [Coder Discord](https://discord.gg/coder)
- **This Template**: Open an issue in this repository
