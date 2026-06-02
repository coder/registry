---
display_name: Incus VM
description: Run a full virtual machine on a remote Incus host
icon: ../../../../.icons/lxc.svg
verified: false
tags: [local, incus, vm, virtual-machine]
---

# Incus VM

Provision a full KVM virtual machine on an [Incus](https://linuxcontainers.org/incus/) host. Unlike the system container template, this creates an isolated VM with its own kernel. Images are pulled from [images.linuxcontainers.org](https://images.linuxcontainers.org) and cached on the host.

Unlike the upstream `coder/incus` template, this variant:

- Launches a **virtual machine** (`type = "virtual-machine"`) instead of a system container
- Supports **remote Incus hosts** via `incus remote add` — the Coder provisioner does not need to be on the same machine as Incus
- Handles **token rotation** on every workspace start via a `null_resource` provisioner

## Prerequisites

### 1. Install Incus on the VM host

Follow the [Incus installation guide](https://linuxcontainers.org/incus/docs/main/installing/) for your distro. On Debian/Ubuntu:

```sh
sudo apt-get install incus
sudo incus admin init
```

Verify it's running:

```sh
incus list
```

### 2. Add the host as a remote on the Coder provisioner

The Coder provisioner (the machine running `coderd` or a provisioner daemon) needs to reach the Incus API on the VM host. Run these commands **on the Coder provisioner**.

**On the VM host** — generate a trust token:

```sh
incus config trust add coder-provisioner
```

This prints a one-time token. Copy it.

**On the Coder provisioner** — add the remote using that token:

```sh
incus remote add my-server https://<host-ip-or-hostname>:8443 --token <paste-token-here>
```

Verify connectivity:

```sh
incus list my-server:
```

> **Tip:** The remote name you use here (`my-server` in the example) is what you'll enter in the **Incus Remote** workspace parameter. Add one `option` block per remote in `main.tf`.

### 3. Create a storage pool on the VM host

The template uses an Incus storage pool to back the VM root disk. If you don't already have one, create it on the VM host:

```sh
incus storage create default btrfs
```

Or to back it with a specific directory or block device:

```sh
incus storage create hdd btrfs source=/data/incus-pool
```

List existing pools:

```sh
incus storage list
```

Set the pool name in the **Storage Pool** workspace parameter (default: `default`).

### 4. Ensure the VM host has KVM

VMs require hardware virtualisation. Check on the host:

```sh
ls /dev/kvm
```

If the device is missing, enable virtualisation in your BIOS/UEFI or, in a nested setup, pass through the kvm module.

### 5. Add image options (optional)

Images are cached automatically from `images.linuxcontainers.org` when a workspace is first created. You can pre-cache an image manually on the host to speed up the first launch:

```sh
incus image copy images:ubuntu/noble/cloud/amd64 local: --vm --alias ubuntu/noble/cloud/amd64
```

List cached images:

```sh
incus image list
```

To add a custom image option, edit `main.tf` and add an `option` block inside `data.coder_parameter.image`.

## Usage

1. Push this template to your Coder deployment:

   ```sh
   coder templates push incus-vm --directory .
   ```

2. Create a workspace and select your Incus remote, image, and resource sizes.

3. Connect via `coder ssh <workspace>` or open VS Code in the browser.

## Adding additional remotes

Edit the `data.coder_parameter.remote` block in `main.tf` and add an `option` for each host:

```terraform
option {
  name  = "my-server"
  value = "my-server"
}
```

The `value` must exactly match the remote name shown in `incus remote list` on the provisioner.
