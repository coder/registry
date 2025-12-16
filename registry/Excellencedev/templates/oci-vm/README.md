---
display_name: Oracle Cloud VM (Linux)
description: Provision Oracle Cloud Infrastructure (OCI) instances as Coder workspaces
icon: ../../../../.icons/oracle.svg
verified: false
tags: [vm, linux, oracle, oci]
---

# Remote Development on Oracle Cloud Infrastructure (OCI)

Provision OCI virtual machines as [Coder workspaces](https://coder.com/docs/workspaces) using this Terraform template.

## Prerequisites

To deploy Coder workspaces on Oracle Cloud, you’ll need the following:

### OCI Resources

Before deploying, ensure your Oracle Cloud tenancy has:

- A **VCN (Virtual Cloud Network)** already created
- At least one **subnet** within that VCN (can be public or private)
- An **Internet Gateway** attached to the VCN
- A **Route Table** that routes `0.0.0.0/0` traffic to the Internet Gateway

> [!NOTE]
> This template **does not create networking resources** (VCN, subnet, gateway, etc.).  
> You must reference an existing subnet using its **OCID** via the `subnet_id` variable.

### OCI Authentication

You’ll also need the following credentials:

- **Tenancy OCID**
- **User OCID**
- **Fingerprint**
- **Private Key**
- **Compartment OCID**(Optional) default to Tenancy OCID if not defined
- **Subnet OCID**

[OCI Documentation](https://docs.oracle.com/en-us/iaas/Content/dev/terraform/configuring.htm#api-key-auth)

---

## Example `.tfvars` File

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..xxxx"
user_ocid        = "ocid1.user.oc1..xxxx"
fingerprint      = "aa:bb:cc:dd:ee:ff"
subnet_id        = "ocid1.subnet.oc1.eu-marseille-1.aaaaaaaaxxx"
region           = "eu-marseille-1"
private_key = <<EOT
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASC...
-----END PRIVATE KEY-----
EOT
```