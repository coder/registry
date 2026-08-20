---
display_name: Incus NixOS VM
description: Run a NixOS virtual machine on a local Incus host
icon: ../../../../.icons/lxc.svg
verified: false
tags: [local, incus, vm, nixos]
---

# Incus NixOS VM

Provision a NixOS KVM virtual machine on an [Incus](https://linuxcontainers.org/incus/) host. The image is pulled from [images.linuxcontainers.org](https://images.linuxcontainers.org) and cached on the host.

NixOS does not support cloud-init. This template uses `nixos-rebuild switch` via `incus exec` to configure the workspace user and start the Coder agent. The rebuild only runs on first boot; subsequent starts rotate the agent token and restart the service directly.

## Prerequisites

### 1. Install Incus on the VM host

Follow the [Incus installation guide](https://linuxcontainers.org/incus/docs/main/installing/) for your distro. On Debian/Ubuntu:

```sh
sudo apt-get install incus
sudo incus admin init
```

### 2. Run the Coder provisioner on the same machine

This template uses the local Incus socket, so the Coder provisioner must run on the same machine as Incus. See [provisioner daemons](https://coder.com/docs/admin/provisioners).

### 3. Ensure the host has KVM

```sh
ls /dev/kvm
```

If the device is missing, enable virtualisation in your BIOS/UEFI or, in a nested setup, pass through the `kvm` module.

### 4. Create a storage pool (if needed)

```sh
incus storage create default btrfs
incus storage list
```

### 5. Push the template

```sh
# amd64 host:
coder templates push incus-nixos --directory . --variable arch=amd64

# arm64 host:
coder templates push incus-nixos --directory . --variable arch=arm64
```

The `storage_pool` variable defaults to `default`. Override if needed:

```sh
coder templates push incus-nixos --directory . \
  --variable arch=arm64 \
  --variable storage_pool=fast-nvme
```

The `nixos_channel` variable controls which NixOS channel is used for `nixos-rebuild`. It must match the image version (default: `nixos-25.11`).

## Usage

1. Create a workspace from this template and choose CPU, memory, and disk.
2. Connect via `coder ssh <workspace>` or use VS Code in the browser via the [VS Code extension](https://coder.com/docs/user-guides/workspace-access/vscode).
3. Install packages declaratively by editing `/etc/nixos/coder.nix` and running `sudo nixos-rebuild switch`.

## Notes

- `code-server` is not installed by this template. The Coder agent is started as a plain systemd service. Install editors via nix packages in `coder.nix`.
- The first workspace start takes several minutes while `nixos-rebuild switch` runs. Subsequent starts are fast.
- Advanced Incus remotes (targeting a separate host over the network) are not supported by this template. See the `incus-vm` template for guidance on adding remote support.
