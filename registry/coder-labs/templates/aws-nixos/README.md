---
display_name: AWS EC2 (NixOS)
description: Provision NixOS EC2 VMs as Coder workspaces from a flake
icon: ../../../../.icons/nixos.svg
verified: true
tags: [vm, linux, aws, nixos, persistent-vm]
---

# NixOS workspaces on AWS EC2

Boot an EC2 workspace from a Git flake. NixOS rebuilds before the agent starts.

## Before you start

- Give the Coder provisioner AWS credentials through the usual provider credential chain.
  See the [EC2 policy example](../../../coder/templates/aws-linux/PREREQUISITES.md); its `RunInstances` and `CreateTags` permissions cover more than tagged resources.
- Keep a default VPC/subnet. Allow provisioner egress to AWS/JetBrains and VM egress to Coder/Git/Nix caches.
- Use a supported Git URL: `https://host/org/repo` or `git+ssh://git@host/org/repo`, with optional `?ref=branch`.
  `github:` and `?dir=` are not supported. Commit your flake before starting a workspace.

## Choose a flake

**Start with the [example flake](https://github.com/coder/nixos-example-flake):**

1. Fork it, edit `configuration.nix`, and commit your changes and `flake.lock`.
2. Set `flake_ref` to your fork's Git URL. Keep the default `flake_attr = "coder-workspace-ec2-$ARCH"`.
3. Push the template and create a workspace. Its default instance type is `t3.medium`.

**Bring an existing flake:**

1. Add `github:coder/nixos-modules` as an input. Import `coder-modules.nixosModules.default` in each workspace host.
2. Include EC2 hardware support; the [example hardware module](https://github.com/coder/nixos-example-flake/blob/main/hardware/ec2.nix) imports the boot-critical NixOS Amazon image module.
3. Set each host's `nixpkgs.hostPlatform` and `coder.flakeAttr` to its own `nixosConfigurations` name.
4. Export hosts for the instance types you offer. Use `$ARCH` in `flake_attr` for paired `x86_64`/`aarch64` names, or a fixed name for one architecture.
5. Set `flake_ref` and `flake_attr`, push the template, then create a workspace.

Instance type determines AMI, agent architecture, and `$ARCH`. Small sizes may lack build memory.

## Work with the workspace

Boot syncs `/etc/nixos` and rebuilds. Dirty trees and local commits stay untouched. To rebuild manually:

```console
sudo nixos-rebuild switch --flake /etc/nixos#coder-workspace-ec2-x86_64
```

Use your host's attribute instead of the example name. The root disk and Nix store survive stop/start, **not** instance deletion or replacement. A larger root disk can be selected later; EBS cannot shrink it.

Watch the **NixOS** workspace log or `/var/log/coder-nixos/rebuild-latest.log`. If first boot has no agent, use EC2 console output:

```console
aws ec2 get-console-output --instance-id <instance-id> --output text
```

## Secrets and limitations

Do not put secrets in Nix expressions: the Nix store is readable on the VM. Workspace facts and optional bootstrap files are not secret storage. The agent token is kept out of Nix, but EC2 user-data and Terraform state contain it; restrict access to both. Processes with instance-metadata access can read user-data.

Private repos need root Git credentials before first boot and root Nix input credentials; this template supplies neither. HTTP URL credentials in `flake_ref` are rejected. NixOS scripts need `#!/usr/bin/env bash`; downloaded IDE binaries need `programs.nix-ld`.

Existing templates may retain a stored legacy `flake_attr`; update that variable explicitly before rebuilding against renamed example-flake hosts.
