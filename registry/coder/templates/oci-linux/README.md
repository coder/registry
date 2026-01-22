---
display_name: Oracle Cloud Infrastructure (Linux)
description: Provision OCI compute instances as Coder workspaces
icon: ../../../../.icons/cloud-devops.svg
verified: false
tags: [vm, linux, oci]
---

# Remote Development on Oracle Cloud Infrastructure (Linux)

Provision OCI compute instances as Coder workspaces.

## Prerequisites

### Authentication

This template assumes you have configured the OCI Terraform provider with API key
credentials. The provider supports configuration through environment variables,
`~/.oci/config`, or Terraform variables. See the OCI provider docs for details:

- https://registry.terraform.io/providers/oracle/oci/latest/docs

You will need:

- Tenancy OCID
- User OCID
- Fingerprint
- Private key
- Region

### Required inputs

Provide these values when using the template:

- `tenancy_ocid`
- `compartment_ocid`

## Architecture

This template provisions the following resources:

- VCN, subnet, route table, and internet gateway
- OCI compute instance
- Boot volume size configured per workspace

> Note: This template is designed to be a starting point. Edit the Terraform to
> customize networking, images, or storage policies.

## code-server

`code-server` is installed via the `coder_agent` init script, and exposed in the
Coder UI through the `code-server` module.
