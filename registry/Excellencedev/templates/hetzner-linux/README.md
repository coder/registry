---
display_name: Hetzner Cloud Server
description: Provision Hetzner Cloud servers as Coder workspaces
icon: ../../../../.icons/hetzner.svg
tags: [vm, linux, hetzner]
---

# Remote Development on Hetzner Cloud (Linux)

Provision Hetzner Cloud servers as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

> [!WARNING]
> **Workspace Storage Persistence:** When a workspace is stopped, the Hetzner Cloud server instance is stopped but your home volume and stored data persist. This means your files and data remain intact when you resume the workspace.

> [!IMPORTANT]
> **Volume Management & Costs:** Hetzner Cloud volumes persist even when workspaces are stopped and will continue to incur storage costs (€0.0476/GB/month). Volumes are only automatically deleted when the workspace is completely deleted. Monitor your volumes in the [Hetzner Cloud Console](https://console.hetzner.cloud/) to manage costs effectively.

## Prerequisites

To deploy workspaces as Hetzner Cloud servers, you'll need:

- Hetzner Cloud [API token](https://console.hetzner.cloud/projects) (create under Security > API Tokens)

### Authentication

This template assumes that the Coder Provisioner is run in an environment that is authenticated with Hetzner Cloud.

Obtain a Hetzner Cloud API token from your [Hetzner Cloud Console](https://console.hetzner.cloud/projects) and provide it as the `hcloud_token` variable when creating a workspace.
For more authentication options, see the [Terraform provider documentation](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs#authentication).

> [!NOTE]
> This template is designed to be a starting point. Edit the Terraform to extend the template to support your use case.
