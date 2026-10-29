---
display_name: Incus (NixOS)
description: Provision NixOS virtual machines on an Incus host as Coder workspaces, configured from a flake
icon: ../../../../.icons/nixos.svg
verified: true
tags: [vm, linux, incus, nixos, persistent-vm]
---

# Incus (NixOS)

Boot a NixOS virtual machine on an [Incus](https://linuxcontainers.org/incus/) host, local or remote (including [IncusOS](https://linuxcontainers.org/incus-os/)), from a Git flake. NixOS rebuilds before the agent starts, using the [Nix(OS) module](../../modules/nix). This is the Incus counterpart of the [AWS EC2 (NixOS) template](../aws-nixos); the same flake can serve both.

The boot rebuild also uses the nix-community Cachix cache alongside `cache.nixos.org`, via the module's `config`. This covers the first rebuild from the image; persistent cache configuration for the daemon and later manual rebuilds belongs in the flake's `nix.settings`.

## Before you start

- Give the Coder provisioner an Incus client configuration (`$HOME/.config/incus` of the provisioner's user) whose default remote is the Incus host, or set the `remote` variable to name one. For a remote host, add it with a trusted client certificate:

  ```console
  incus remote add my-incus https://incus.example.com:8443
  incus remote switch my-incus
  ```

  On IncusOS, import the client certificate from the install media first: `openssl pkcs12 -in client.pfx -out client.pem -nodes`, then copy the certificate and key to `client.crt` and `client.key` in that directory.

- The host needs KVM and a storage pool. The root disk uses the pool of the default profile's root disk unless `storage_pool` says otherwise; the default profile also provides the network.
- Allow VM egress to Coder, Git and the Nix caches. The provisioner only talks to the Incus API.
- Set `arch` to the host's architecture when pushing the template.
- Use a supported Git URL: `https://host/org/repo` or `git+ssh://git@host/org/repo`, with optional `?ref=branch`.
  Commit your flake before starting a workspace.

## Choose a flake

**Start with the [example flake](https://github.com/coder/nixos-example-flake):**

1. Fork it, edit `configuration.nix`, and commit your changes and `flake.lock`.
2. Set `flake_ref` to your fork's Git URL. Keep the default `flake_attr = "coder-workspace-incus-$ARCH"`.
3. Push the template and create a workspace. Its default size is 2 vCPUs and 4 GiB of memory.

**Bring an existing flake:**

1. Add `github:coder/nixos-modules` as an input. Import `coder-modules.nixosModules.default` in each workspace host.
2. Include Incus VM support; the example's `hardware/incus.nix` imports `incus-virtual-machine.nix` and keeps the image's systemd-networkd setup. The Incus agent it enables is how every workspace start reaches the VM: without it the first rebuild succeeds and later starts never do.
3. Set each host's `nixpkgs.hostPlatform` and `coder.flakeAttr` to its own `nixosConfigurations` name.
4. Export hosts for the architectures you offer. Use `$ARCH` in `flake_attr` for paired `x86_64`/`aarch64` names, or a fixed name for one architecture.
5. Set `flake_ref` and `flake_attr`, push the template, then create a workspace.

## How it boots

Stock NixOS images have no hook that runs user-data, so on every start the template runs a small launcher through the Incus agent. It detaches the bootstrap into the transient `coder-init.service` and returns, so the workspace build does not wait for a rebuild. The bootstrap publishes the agent handoff on a tmpfs, syncs `/etc/nixos`, rebuilds if the flake changed, and starts `coder-agent.service` even when the rebuild fails.

The image ships no `git`; the first boot substitutes it from the image's channel. Later boots skip the rebuild unless the flake changed, so a restart takes seconds. Stopping is graceful, which lets the flake stage the next generation on shutdown.

## Work with the workspace

Boot syncs `/etc/nixos` and rebuilds. Dirty trees and local commits stay untouched. To rebuild manually:

```console
sudo nixos-rebuild switch --flake /etc/nixos#coder-workspace-incus-x86_64
```

Use your host's attribute instead of the example name. The root disk and Nix store survive stop/start, **not** workspace deletion. A larger root disk can be selected later; it cannot shrink.

Watch the **NixOS** workspace log or `/var/log/coder-nixos/rebuild-latest.log`. If the agent never connects, read the bootstrap from the host:

```console
incus exec coder-<owner>-<workspace> -- journalctl -u coder-init
```

Reboots from inside the VM do not rerun the bootstrap, so the agent stays down until the workspace is restarted from Coder.

## Secrets and limitations

Do not put secrets in Nix expressions: the Nix store is readable on the VM. Workspace facts and optional bootstrap files are not secret storage. The agent token is kept out of Nix and out of process arguments, but Terraform state contains it; restrict access to it.

Private repos need Git authentication before first boot and separate credentials for private Nix inputs; this template supplies neither. HTTP credentials in `flake_ref` are allowed but exposed in Terraform state and `/etc/nixos/.git/config`. Prefer root-managed credentials. NixOS scripts need `#!/usr/bin/env bash`; downloaded IDE binaries need `programs.nix-ld`.
