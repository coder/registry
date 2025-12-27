---
display_name: Oracle Cloud Infrastructure (Linux)
description: Provision Oracle Cloud Infrastructure compute instances as Coder workspaces
icon: ../../../../.icons/oci.svg
verified: false
tags: [vm, linux, oci, oracle, persistent-vm]
---

# Remote Development on Oracle Cloud Infrastructure VMs (Linux)

Provision Oracle Cloud Infrastructure (OCI) compute instances as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

## Prerequisites

### Authentication

By default, this template authenticates to OCI using the provider's default [authentication methods](https://registry.terraform.io/providers/oracle/oci/latest/docs#authentication).

The simplest way (without making changes to the template) is via:

1. **API Key Authentication** - Configure `~/.oci/config` with your OCI credentials
2. **Instance Principal** - If running Coder on an OCI instance, use instance principal authentication
3. **Environment Variables** - Set `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY_PATH`, and `OCI_REGION`

For more authentication options, see the [OCI provider documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs#authentication).

### Required Variables

| Variable | Description |
|----------|-------------|
| `compartment_ocid` | The OCID of the compartment to create resources in |
| `vcn_ocid` | (Optional) OCID of existing VCN - creates new if not provided |
| `subnet_ocid` | (Optional) OCID of existing subnet - creates new if not provided |

## Required Permissions / Policy

The following sample IAM policy allows Coder to manage compute instances:

```
Allow group CoderAdmins to manage instance-family in compartment <compartment_name>
Allow group CoderAdmins to manage virtual-network-family in compartment <compartment_name>
Allow group CoderAdmins to read instance-images in compartment <compartment_name>
Allow group CoderAdmins to inspect compartments in tenancy
```

For more granular control:

```
Allow group CoderAdmins to manage instances in compartment <compartment_name> where target.resource.tag.Coder_Provisioned = 'true'
Allow group CoderAdmins to use subnets in compartment <compartment_name>
Allow group CoderAdmins to use vnics in compartment <compartment_name>
Allow group CoderAdmins to use network-security-groups in compartment <compartment_name>
```

## Architecture

This template provisions the following resources:

- OCI Compute Instance (VM.Standard.E4.Flex or VM.Standard.A1.Flex shapes)
- VCN, Subnet, Internet Gateway, Route Table (if not using existing network)

### Instance Shapes

| Shape | Architecture | Description |
|-------|-------------|-------------|
| VM.Standard.E4.Flex | AMD (x86_64) | General purpose AMD EPYC instances |
| VM.Standard.A1.Flex | Arm (aarch64) | Ampere Altra Arm-based instances |

Both shapes support flexible OCPU and memory configuration.

### Networking

If you don't provide existing `vcn_ocid` and `subnet_ocid`, the template creates:
- A VCN with CIDR 10.0.0.0/16
- A public subnet with CIDR 10.0.1.0/24
- An Internet Gateway for outbound access
- Security rules allowing SSH (port 22) ingress

Coder uses instance start/stop actions to manage the VM lifecycle. This template is fully persistent - the full filesystem is preserved when the workspace restarts.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.

## code-server

`code-server` is installed via the `coder_agent` using the code-server module.
The `coder_app` resource is defined to access `code-server` through the dashboard UI.

## OCI Free Tier

OCI offers an Always Free tier that includes:
- 2 AMD-based Compute VMs (VM.Standard.E2.1.Micro)
- 4 Arm-based Ampere A1 cores and 24 GB of memory (VM.Standard.A1.Flex)

To use Free Tier shapes, modify the `instance_shape` parameter options to include:
- `VM.Standard.E2.1.Micro` for AMD
- `VM.Standard.A1.Flex` with up to 4 OCPUs for Arm
