---
display_name: Incus VM
description: Run a full virtual machine on a local Incus host
icon: ../../../../.icons/lxc.svg
verified: false
tags: [local, incus, vm, virtual-machine]
---

# Incus VM

Provision a full KVM virtual machine on an [Incus](https://linuxcontainers.org/incus/) host. Unlike the system container template, this creates an isolated VM with its own kernel. Images are pulled from [images.linuxcontainers.org](https://images.linuxcontainers.org) and cached on the host.

## Prerequisites

### 1. Install Incus on the VM host

Follow the [Incus installation guide](https://linuxcontainers.org/incus/docs/main/installing/) for your distro. On Debian/Ubuntu:

```sh
sudo apt-get install incus
sudo incus admin init
```

Verify it's working:

```sh
incus list
```

### 2. Run the Coder provisioner on the same machine

This template uses Incus via the local Unix socket, so the Coder provisioner (or `coderd` itself) must run on the same machine as Incus. The simplest setup is a [provisioner daemon](https://coder.com/docs/admin/provisioners) running directly on the Incus host.

### 3. Set the architecture when pushing the template

The `arch` variable must match your Incus host's CPU architecture. Pass it when pushing:

```sh
# For amd64 (x86-64) hosts:
coder templates push incus-vm --directory . --variable arch=amd64

# For arm64 (aarch64) hosts:
coder templates push incus-vm --directory . --variable arch=arm64
```

### 4. Ensure the VM host has KVM

VMs require hardware virtualisation. Check on the host:

```sh
ls /dev/kvm
```

If the device is missing, enable virtualisation in your BIOS/UEFI or, in a nested setup, pass through the `kvm` module.

### 5. Create a storage pool (if needed)

The template uses an Incus storage pool to back the VM root disk. If you don't already have one:

```sh
incus storage create default btrfs
```

List existing pools:

```sh
incus storage list
```

The pool name defaults to `default` and can be overridden when pushing the template with `--variable storage_pool=<name>`.

## Usage

1. Push this template to your Coder deployment:

   ```sh
   coder templates push incus-vm --directory . --variable arch=amd64
   ```

2. Create a workspace and select an image and resource sizes.

3. Connect via `coder ssh <workspace>` or open VS Code in the browser.

## Advanced: using a remote Incus host

By default this template connects to the local Incus socket. If you want the provisioner to target a separate Incus host over the network, add a `remote` parameter and use `incus remote add` to register the host on the provisioner machine:

```sh
# On the Incus host — generate a trust token:
incus config trust add coder-provisioner

# On the provisioner — add the remote:
incus remote add my-server https://<host-ip>:8443 --token <paste-token>
```

Then update `main.tf` to accept a `remote` parameter and pass it to the `incus_image` and `incus_instance` resources. See the [Incus remote docs](https://linuxcontainers.org/incus/docs/main/remotes/) for details.
