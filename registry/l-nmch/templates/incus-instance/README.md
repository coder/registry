---
display_name: Incus Instance
description: Provision Instance on Incus/LXD as Coder workspaces
icon: ../../../../.icons/proxmox.svg
verified: false
tags: [incus, lxc, vm, cloud-init, container]
---

> Based on the work of [umair](https://github.com/l-nmch/registry/tree/main/registry/umair)

# Incus VM Template for Coder

Provision Linux VMs & Containers on Incus/LXD as [Coder workspaces](https://coder.com/docs/workspaces). The template deploys an instance with cloud-init, and runs the Coder agent under the workspace owner's Linux user.

## Prerequisites

- Incus server / cluster with exposed API

### Setup the template

1. Create an Incus trust token:

```bash
incus config trust add coder # Save the token
```

2. Setup an Incus project with a network:

```bash
incus project create Coder -c features.network=true
incus network create Main --project Coder
```

3. Prepare `terraform.tfvars` in your environment:

```bash
remote_name = "incus"
remote_address = "https://incus.local:8443"
remote_project = "Coder"
remote_network = "Main"
remote_storage_pool = "local"
remote_token = "<token>"
```

## Use

```bash
coder template push incus-instance -d .
```

## Warnings

Incus often works with cloud image, please use `cloud` tagged images such as `images:ubuntu/22.04/cloud` to be able to use cloud-init (Using non cloud tagged images will lead into your workspaces not working as the coder agent installs through cloud-init)

## References

- Incus: [source](https://linuxcontainers.org/incus/)
- Incus Terraform Provider: [source](https://registry.terraform.io/providers/lxc/incus/latest/docs)
- Coder – Best practices & templates:
  - https://coder.com/docs/tutorials/best-practices/speed-up-templates
  - https://coder.com/docs/tutorials/template-from-scratch