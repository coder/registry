---
display_name: Linode Instance (Linux)
description: Provision Linode instances as Coder workspaces
icon: ../../../../.icons/cloud.svg
verified: false
tags: [vm, linux, linode]
---

# Remote Development on Linode Instances

Provision Linode instances as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

<!-- TODO: Add screenshot -->

## Prerequisites

To deploy workspaces as Linode instances, you'll need:

- Linode [personal access token (PAT)](https://www.linode.com/docs/products/tools/api/guides/manage-api-tokens/)

### Authentication

This template assumes that the Coder Provisioner is run in an environment that is authenticated with Linode.

Obtain a [Linode Personal Access Token](https://cloud.linode.com/profile/tokens) and set the `LINODE_TOKEN` environment variable to the access token.
For other ways to authenticate [consult the Terraform provider's docs](https://registry.terraform.io/providers/linode/linode/latest/docs).

## Architecture

This template provisions the following resources:

- Linode instance (ephemeral, deleted on stop)
- Linode volume (persistent, mounted to `/home/coder`)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the VM image, or use a [startup script](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script).

> [!NOTE]
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
