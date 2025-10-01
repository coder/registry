---
name: Hetzner Cloud Linux Workspace
description: Provision a Hetzner Cloud server with private networking and a persistent home volume for Coder workspaces.
tags: [hetzner, terraform, linux, coder]
icon: /icon/hetzner-cloud.svg
---

# Hetzner Cloud Linux Workspace

This template provisions a single Hetzner Cloud server optimised for Coder. It creates a dedicated private network, attaches
a persistent volume for the workspace home directory, and boots the machine with a cloud-init configuration that installs and
starts the Coder agent automatically.

## Features

- Choice of popular Ubuntu, Debian, Fedora, and Rocky Linux images
- Selectable CPX and CAX instance sizes, including x86 and ARM options
- Private network and firewall pre-configured for secure access
- Persistent ext4 home volume mounted at `/home/<username>`
- Optional code-server and JetBrains module integrations

## Requirements

- Hetzner Cloud project with API access enabled
- Hetzner Cloud API token (`HCLOUD_TOKEN`) with permission to create servers, networks, firewalls, and volumes
- Coder v2.9+ (tested with Terraform >= 1.4)

## Usage

1. Export your Hetzner Cloud token before starting `coderd`:
   ```bash
   export HCLOUD_TOKEN="<your-token>"
   ```
2. Import this template into your Coder workspace namespace (see [Coder template docs](https://coder.com/docs/templates/overview)).
3. When creating a workspace pick the desired location, server type, and image from the parameters sidebar.
4. Launch the workspace – the agent will come online automatically and the persistent volume will mount to the home directory.

## Variables

| Name             | Description                                       | Type     | Default        | Required |
|------------------|---------------------------------------------------|----------|----------------|----------|
| `hcloud_token`   | Overrides the HCLOUD_TOKEN environment variable   | `string` | `""`          | no       |

### Workspace Parameters

| Parameter               | Description                                    |
|-------------------------|------------------------------------------------|
| `Hetzner location`      | Target data centre (nbg1, fsn1, hel1, ash, hil) |
| `Server type`           | CPX/CAX instance family                         |
| `Server image`          | Linux distribution image                        |
| `Home volume size`      | Persistent volume size in GiB (10 – 1024)       |
| `Private network CIDR`  | CIDR for the created private network            |
| `Subnet CIDR`           | CIDR for the workspace subnet                   |

## Resources Created

- `hcloud_network` and `hcloud_network_subnet` for workspace isolation
- `hcloud_firewall` allowing SSH/HTTP/HTTPS ingress and full egress
- `hcloud_volume` formatted as ext4 and attached to the workspace server
- `hcloud_server` with user-data to start the Coder agent
- Optional `code-server` and `jetbrains` Coder modules for IDE support

## Customisation

- Adjust the default network ranges in the parameter definitions if they conflict with existing infrastructure.
- Update the `startup_script` in `coder_agent.main` to install language runtimes or tooling specific to your team.
- Add extra firewall rules or attach additional volumes as needed.

## Troubleshooting

### Workspace fails to start and reports unreachable agent
- Verify that the HCLOUD_TOKEN exported for `coderd` has `Read & Write` permissions.
- Check the Hetzner Cloud console for the server logs – ensure the agent service is running (`systemctl status coder-agent`).

### Volume not mounted on first boot
- Hetzner volumes can take a few seconds to attach. Restarting the instance or re-running `systemctl start coder-agent`
  after attachment will complete the mount.

## Contributing

Improvements and additional server options are welcome! Please read the [contributing guidelines](../../../../CONTRIBUTING.md)
before submitting a pull request.
