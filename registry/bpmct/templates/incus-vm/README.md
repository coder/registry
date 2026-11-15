---
display_name: Incus VM
description: Run a Linux or Windows virtual machine on a local Incus host
icon: ../../../../.icons/lxc.svg
verified: false
tags: [local, incus, vm, virtual-machine, windows]
---

# Incus VM

Run a KVM virtual machine on an [Incus](https://linuxcontainers.org/incus/) host as a Coder workspace. Linux images come from [images.linuxcontainers.org](https://images.linuxcontainers.org). Windows uses a golden image that you build one time on the host.

## Prerequisites

- An Incus host with KVM. Make sure that `/dev/kvm` exists. See the [Incus installation guide](https://linuxcontainers.org/incus/docs/main/installing/).
- A Coder [provisioner](https://coder.com/docs/admin/provisioners) on the same host. The template uses the local Incus socket.
- An Incus storage pool. `incus storage list` shows the pools.

Windows workspaces also need:

- An amd64 host.
- `genisoimage` on the provisioner machine.
- A Windows golden image on the Incus host. See [Windows](#windows).

## Usage

Push the template. Set `arch` to `amd64` or `arm64` to match the host, and set `storage_pool` to your pool.

```sh
coder templates push incus-vm -d . --variable arch=amd64 --variable storage_pool=default
```

Then create a workspace and select an image.

## Architecture

Each workspace is one Incus VM. The VM stops when the workspace stops, and the root disk stays until you delete the workspace.

Linux VMs get the Coder agent from cloud-init. A `null_resource` writes the new agent token into the VM on each start with `incus exec`.

Incus has no guest agent for Windows, so `incus exec` and cloud-init do not work there. On each start, the template writes the agent token to a small ISO, attaches the ISO to the stopped VM, and starts the VM. A scheduled task in the golden image reads the token, downloads the Coder agent, and runs it. The [windows-rdp](https://registry.coder.com/modules/coder/windows-rdp) module adds RDP in the browser.

## Windows

The steps below were tested on Ubuntu 24.04 with Incus 6.0 and QEMU 8.2. On that host, Windows did not boot with the Incus defaults. The template and the steps use legacy BIOS boot (`security.csm=true`) and `raw.qemu="-cpu host"` for that reason.

### Build the golden image

Run these commands on the Incus host, from this template directory. Replace `default` with your storage pool.

1. Install the tools. Incus looks for SeaBIOS in the OVMF directory, so add a link.

   ```sh
   sudo apt-get install -y genisoimage wimtools libwin-hivex-perl rsync seabios
   sudo snap install distrobuilder --classic
   sudo ln -sf /usr/share/seabios/bios-256k.bin /usr/share/OVMF/seabios.bin
   ```

2. Download the [Windows Server 2022 evaluation ISO](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022) as `windows.iso` and the [virtio-win ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) as `virtio-win.iso`.

3. Add the virtio drivers to the Windows ISO. Windows cannot see the Incus disk without them.

   ```sh
   sudo distrobuilder repack-windows windows.iso windows-virtio.iso --drivers=virtio-win.iso --windows-version=2k22
   ```

4. Make an ISO from the `windows` directory. It holds the answer file for the unattended install and the scripts that set up the Coder agent.

   ```sh
   genisoimage -o coder-build.iso -V CODER_BUILD -udf -iso-level 4 -J -R windows
   ```

5. Create the VM and start the install.

   ```sh
   incus storage volume import default windows-virtio.iso windows-install --type=iso
   incus storage volume import default coder-build.iso coder-build --type=iso
   incus init windows-golden --empty --vm -s default -d root,size=60GiB \
     -c security.csm=true -c security.secureboot=false -c raw.qemu="-cpu host" \
     -c limits.cpu=4 -c limits.memory=8GiB
   incus config device add windows-golden install disk pool=default source=windows-install boot.priority=10
   incus config device add windows-golden build disk pool=default source=coder-build
   incus start windows-golden
   ```

6. Wait for the install. It needs no input, but the VM needs internet access to update Microsoft Defender. The VM restarts during the install, and `incus list windows-golden` can show `STOPPED` for a moment. The install is complete when the state stays at `STOPPED`. In testing, this took approximately one hour. If the VM does not stop, run `incus console windows-golden --type=vga` to see the error.

7. Publish the image. The template looks for the `windows-server-2022` alias. Use the `windows_image` variable to change it.

   ```sh
   incus config device remove windows-golden install
   incus config device remove windows-golden build
   incus publish windows-golden --alias windows-server-2022
   ```

### Use a Windows workspace

Select the Windows Server 2022 image, 4 CPUs or more, and 8 GB of memory or more. The disk is 60 GB or larger, and `C:` grows to fill it. The agent connects approximately 6 minutes after the first start and in less than 1 minute after later starts.

Open the Web RDP app, or use `coder ssh`.

> [!WARNING]
> The windows-rdp module sets the `Administrator` password to `coderRDP!`. To change it, set `admin_password` on the module in `windows.tf`.

> [!NOTE]
> The golden image does not use Sysprep. All workspaces have the same hostname and machine SID. Do not join them to a domain. The evaluation ISO gives a license for 180 days.

## Use a remote Incus host

The template connects to the local Incus socket. To use a different host, add it as a remote on the provisioner machine.

```sh
# On the Incus host:
incus config trust add coder-provisioner

# On the provisioner machine:
incus remote add my-server https://HOST_IP:8443 --token TOKEN
```

Then set `remote` on the `incus_image` and `incus_instance` resources, and add the `my-server:` prefix to the `incus` commands in `main.tf` and `windows.tf`. See the [Incus remote docs](https://linuxcontainers.org/incus/docs/main/remotes/).
