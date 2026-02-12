---
display_name: Oracle Cloud Infrastructure (Linux)
description: Provision OCI VMs as Coder workspaces
icon: ../../../../.icons/oci.svg
verified: false
tags: [vm, linux, oci]
---

# Remote Development on Oracle Cloud Infrastructure (OCI)

Provision OCI VMs as [Coder workspaces](https://coder.com/docs/workspaces) with this template.

## Prerequisites

### Oracle Cloud Infrastructure Account
You need an active OCI account.

### Required Variables
To use this template, you must provide the following variables. These can be found in your OCI Console.

1.  **tenancy_ocid**: The OCID of your tenancy. Found in **Governance & Administration** -> **Tenancy Details**.
2.  **user_ocid**: The value of the specific user's OCID. Found in **Identity** -> **Users**.
3.  **fingerprint**: Create an API key for the user (in **User Details** -> **API Keys**) and get the fingerprint.
4.  **private_key_path**: The local path to the private key file corresponding to the public key you uploaded. This path must be accessible by the Coder server or provisioner.
5.  **region**: Your OCI region (e.g., `us-ashburn-1`).
6.  **compartment_ocid**: The OCID of the compartment where resources will be created.
7.  **image_id**: The OCID of the Linux image (e.g., Ubuntu 22.04) you want to use.
    *   Go to **Compute** -> **Platform Images** to find the generic image OCID for your region (e.g. `Canonical Ubuntu`).

## Resources Created
- VCN, Subnet, Internet Gateway, Route Table
- OCI Compute Instance (default shape: VM.Standard.A1.Flex)
