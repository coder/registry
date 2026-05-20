---
display_name: "Oracle Cloud Infrastructure Linux"
description: "Provision OCI Compute instances as Coder workspaces"
icon: "../../../../.icons/cloud-devops.svg"
verified: false
tags: [vm, linux, oci, oracle-cloud, persistent-vm]
---

# Oracle Cloud Infrastructure Linux

Provision Oracle Cloud Infrastructure Compute instances as [Coder workspaces](https://coder.com/docs/workspaces).

## Prerequisites

### Authentication

This template uses the Oracle Cloud Infrastructure Terraform provider and its default authentication methods. Configure the Coder provisioner environment with OCI credentials before pushing this template.

Common options include:

- `OCI_CONFIG_FILE` and `OCI_PROFILE`
- `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY`, and `OCI_REGION`
- instance principals or resource principals when your Coder provisioner runs in OCI

If your Coder server or provisioner runs in a container and you authenticate with an OCI config file, mount both the config file and private key file into the container and set `OCI_CONFIG_FILE` and `OCI_PROFILE` accordingly.

Set `tenancy_ocid` to use the root compartment by default. Set `compartment_ocid` only when workspaces should be created in a child compartment.

### Required permissions

The OCI principal used by Terraform needs permission to manage these resources in the selected compartment:

- Compute instances
- Virtual cloud networks, subnets, internet gateways, route tables, and security lists
- Images lookup

For example, grant a dynamic group or user group permissions similar to:

```text
Allow group <group-name> to manage instance-family in compartment <compartment-name>
Allow group <group-name> to manage virtual-network-family in compartment <compartment-name>
Allow group <group-name> to read app-catalog-listing in tenancy
Allow group <group-name> to read repos in tenancy
```

Adjust the policy to match your organization's compartment and identity model.

## Architecture

This template provisions:

- One VCN with an internet gateway
- One public subnet with outbound internet access
- A security list that allows outbound traffic for package downloads and the Coder agent tunnel
- One OCI Compute instance running Ubuntu
- A configurable boot volume size
- Coder agent metadata for CPU, memory, and disk usage
- code-server and JetBrains modules

The instance is set to `RUNNING` while the workspace is started and `STOPPED` while the workspace is stopped. The boot volume is preserved by OCI, so the workspace filesystem persists between starts.

## Notes

This template intentionally does not open inbound SSH by default. Coder access is provided through the Coder agent. Add explicit ingress rules if your environment requires direct SSH for break-glass access.
