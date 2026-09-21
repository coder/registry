---
display_name: AWS EC2 (NixOS)
description: Provision NixOS EC2 VMs as Coder workspaces from a flake
icon: ../../../../.icons/nixos.svg
verified: false
tags: [vm, linux, aws, nixos, persistent-vm]
---

# Remote development on NixOS AWS EC2 VMs

Provision NixOS EC2 instances as [Coder workspaces](https://coder.com/docs/workspaces), configured
declaratively from a flake in a Git repository. The Coder agent is declared as a NixOS systemd unit,
so it survives `nixos-rebuild` and the workspace stays reachable across configuration changes. The
reference configuration lives at [coder/nixos-example-flake](https://github.com/coder/nixos-example-flake);
point the template at your own fork to control the environment.

<!-- TODO: Add screenshot -->

## Prerequisites

### Authentication

This template authenticates to AWS using the provider's default [authentication methods](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration).

The simplest way is to set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in the environment of the
Coder provisioner. See [PREREQUISITES.md](./PREREQUISITES.md) for the IAM policy, the default VPC
requirement, and the reasons credentials must not be passed as template variables.

## How it works

The template does not build anything itself. It launches an official NixOS AMI and hands the
instance three things: the agent token, the agent init script, and a flake reference. The instance
then applies that flake.

```text
Terraform  ──user-data──▶  amazon-init  ──▶  nixos-rebuild switch  ──▶  coder-agent.service
                            (every boot)       (from your flake)       (started once it finishes)
```

The NixOS AMI does not run cloud-init. It runs `amazon-init.service`, which reads
`/etc/ec2-metadata/user-data` and execs it as a shell script when it begins with `#!` — after
`multi-user.target`, on every boot. The template's script writes the agent handoff, generates the
per-workspace Nix values, and runs one `nixos-rebuild switch`.

User-data itself is a short self-extracting wrapper: the boot script, its two libraries and the
agent init script come to roughly 19 KiB against EC2's 16 KiB limit, so it ships compressed and
unpacks to `/run/coder/bootstrap.sh` — which is also where to look when debugging a boot.

**The agent only starts once the rebuild has finished**, so a build that has work to do shows no
agent while it runs — minutes on a first create, usually seconds afterwards. Progress is streamed
to a workspace log source named "NixOS" while that happens, and `connection_timeout` is raised to
20 minutes so a normal first build does not look like a failure.

That delay is deliberate. `coder-agent.service` is declared without `wantedBy`, so systemd never
starts it on its own and the boot script starts it explicitly after the switch. Left to systemd the
agent would come up at `multi-user.target`, which on every boot after the first is _before_
`amazon-init` has fetched the new commit and rebuilt: the workspace would be reported ready and its
startup scripts would install into a generation that is about to be replaced. A workspace that is
late is better than a workspace that is wrong.

If the rebuild fails, the boot script starts the agent anyway — a workspace whose flake does not
build is exactly the one you need a terminal on.

## Choosing which configuration is applied

Two variables control this:

| Variable     | Default                                                     | Meaning                                        |
| ------------ | ----------------------------------------------------------- | ---------------------------------------------- |
| `flake_ref`  | `git+https://github.com/coder/nixos-example-flake?ref=main` | where the flake lives                          |
| `flake_attr` | `workspace-$ARCH`                                           | which `nixosConfigurations` attribute to apply |

`flake_attr` is the part after `#` in a flake reference, so this is exactly the selection you would
make by hand:

```console
nixos-rebuild switch --flake 'github:your-org/config#workspace-x86_64'
```

`$ARCH` in `flake_attr` is replaced with `x86_64` or `aarch64` to match the chosen instance type.
That keeps the AMI architecture, `coder_agent.arch` and the flake attribute in agreement — they are
all derived from one map in `main.tf`, so a Graviton instance type cannot accidentally boot an
x86 configuration. If you keep a single configuration instead, set `flake_attr` to a fixed name and
only offer instance types of the matching architecture.

Any reference `nixos-rebuild --flake` understands works, including `github:owner/repo`,
`git+ssh://` for private repositories, and `?dir=subdir` for a flake in a subdirectory. The
configuration must be committed: a Git flake reference only ever sees committed files.

## Values passed into the flake

None. The flake is evaluated exactly as written, with no `--override-input`, no `--impure` and no
injected inputs — which is what makes the command the template runs reproducible by hand.

Per-workspace facts are published as a runtime file instead:

```json
// /run/coder/workspace.json, mode 0644
{
  "workspace": "my-workspace",
  "owner": "jane",
  "owner_name": "Jane Doe",
  "owner_email": "jane@example.com",
  "access_url": "https://coder.example.com",
  "hostname": "my-workspace"
}
```

It cannot be an evaluation input: a pure flake may not read an absolute path outside itself, so
consuming it at eval time would need `--impure` and would stop `nixos-rebuild switch` from
reproducing what the template applied. A configuration that wants these values reads the file from
a service at runtime.

Git identity is not in the flake's hands either — it comes from the
[git-config](https://registry.coder.com/modules/coder/git-config) module, which configures the
workspace user's `~/.gitconfig` after the rebuild.

> [!IMPORTANT]
> Never pass a secret into Nix — not as an input, `--argstr` or `builtins.getEnv`. It is copied
> into `/nix/store`, which is world-readable to every process on the workspace and persists across
> generations and past rotation. The agent token is deliberately handed over through `/run/coder`
> at runtime instead, at mode 0600 on a tmpfs, so that it never reaches Nix.

## Rebuilding by hand

The configuration is a git checkout at `/etc/nixos`, owned by the workspace
user, and that is what the template builds. So the command is the ordinary one:

```console
sudo nixos-rebuild switch --flake /etc/nixos#workspace-x86_64
```

No overrides, no `--impure`, no injected inputs — what you get by hand is
exactly what the template applies. The attribute is shown in the workspace's
`Flake URI` metadata and in the boot log.

> [!NOTE]
> A bare `sudo nixos-rebuild switch` only works if your flake exposes a
> configuration named after the machine's hostname, which is what
> `nixos-rebuild` defaults to. The example flake uses per-architecture names
> instead, so pass `--flake /etc/nixos#<attr>`. If your workspaces have stable
> names, naming the configuration after the hostname makes the bare form work.

On every boot the template syncs the checkout: it clones if missing,
fast-forwards a clean checkout on its tracking branch, and **leaves a dirty
tree or local commits alone** and builds those instead. So edits survive a
restart, and the machine tracks upstream until you change something.

A flake built from a git checkout ignores untracked files — `git add` a new
`.nix` file or the rebuild will not see it.

## Keeping workspaces up to date

The `update_process` parameter decides how a periodic rebuild is applied:

- **`boot` (default)** — builds the new configuration and makes it the boot default without
  activating it. Nothing restarts while you are working; the change lands on your next workspace
  restart. The "NixOS" metric in the workspace header shows `(restart to apply update)` when a
  generation is staged.
- **`switch`** — activates immediately, restarting any service whose definition changed.

The schedule comes from the `update_schedule` variable, default `0 0 4 * * *` (04:00 daily).

> [!NOTE]
> `update_schedule` is a **six** field cron expression with seconds first, evaluated in the
> workspace's own timezone. A five field expression is silently misinterpreted rather than
> rejected, and descriptors like `@daily` pass validation but then fail on the agent. Set
> `time.timeZone` in your configuration so the schedule means what you intend.

Set `update_schedule = ""` to disable periodic rebuilds entirely.

To rebuild immediately:

```console
sudo nixos-rebuild switch --flake 'git+https://github.com/coder/nixos-example-flake?ref=main#workspace-x86_64' \
  --override-input coder-vars path:/etc/coder/vars --no-write-lock-file --refresh
```

## Where the logs are

The workspace UI streams `nixos-rebuild`'s own output under a log source named **NixOS** — the same
lines you would see in a terminal. Three kinds of noise are dropped: the enumerated store paths
under `these N derivations will be built:`, per-derivation compiler output, and the expected
`not writing modified lock file` notice. The complete transcript is on the instance:

```console
/var/log/coder-nixos/rebuild-latest.log      # symlink to the most recent run
/var/log/coder-nixos/coder-script.log        # the periodic rebuild script
```

Keeping compiler output out of the UI is not cosmetic. Coder caps agent logs at **1 MiB per
agent**, shared across every log source, and exceeding it does not truncate — the log is marked
overflowed and all later logs for that agent are dropped permanently. The template budgets itself
to half the cap and goes quiet with a pointer to the transcript if it ever gets there.

## Persistence

The instance is stopped and started rather than destroyed and recreated, so the root volume — and
with it `/home` and the Nix store — persists across workspace restarts.

Two lifecycle settings make that safe, and both matter:

- `ignore_changes = [ami]` — the official NixOS AMIs are republished weekly and garbage-collected
  after 90 days. Without this, a new AMI id would replace every live workspace and destroy its root
  volume. The side effect is that **changing `nixos_release` only affects newly created
  workspaces**; existing ones keep their AMI and get their packages from your flake's nixpkgs pin
  anyway.
- `user_data_replace_on_change = false` — the agent token is inside user-data and rotates on every
  start, so user-data changes on every start. With replacement enabled, every restart would destroy
  the volume.

`root_volume_size` is mutable: the AMI enables `boot.growPartition` and `autoResize`, so a larger
volume is picked up on the next restart.

## Architecture support

Both `x86_64` and `arm64` (Graviton) instance types are offered. The AMI filter,
`coder_agent.arch` and the flake attribute are all derived from the instance type, so they cannot
disagree — but your flake must expose a configuration for the architecture you select. The
reference flake ships `workspace-x86_64` and `workspace-aarch64`.

The smallest instance type offered is `t3.medium` on purpose: the NixOS AMI configures no swap and
the Nix store shares the root volume, so a rebuild that has to compile anything will exhaust a
1–2 GiB instance.

## Troubleshooting

### The workspace has been building for a long time

Expected whenever there is a rebuild to do, and always on first create: the agent is not started
until `nixos-rebuild switch` finishes. Watch the "NixOS" log source. A cold closure on a small
instance can take ten minutes or more. A restart with nothing to rebuild skips straight to starting
the agent.

### The agent never connects

The boot script writes its handoff to `/run/coder` before doing anything else, so the usual cause is
a failed rebuild — or, if there are no logs at all, an instance with no route to the internet (a
NixOS workspace fetches its own configuration on boot, so it needs egress before it can report
anything). The workspace metadata shows the instance id; the AMI logs to the serial console, which
needs no SSH:

```console
aws ec2 get-console-output --instance-id i-0123456789abcdef0 --output text
```

On the instance:

```console
systemctl status amazon-init coder-agent
journalctl -u amazon-init -b
cat /var/log/coder-nixos/rebuild-latest.log
```

### A configuration change broke the workspace

`nixos-rebuild switch` builds before it activates, so a configuration that fails to _build_ never
touches the running system — the previous generation keeps running and the failure appears in the
logs. If a configuration builds but misbehaves, roll back:

```console
sudo nixos-rebuild switch --rollback
```

There is deliberately no automatic rollback: on a fresh instance the previous generation is the bare
AMI, which has no Coder agent at all, so rolling back automatically would trade a visible failure
for an unreachable workspace.

### Recovering an unreachable instance

`aws ec2 get-console-output` above needs no access to the instance at all and is usually enough.

For a shell, the AMI enables OpenSSH and `amazon-ssm-agent`. Neither is reachable out of the box —
the template attaches no key pair and the default security group allows no inbound traffic — so
attach what you need for the session with the AWS CLI and detach it afterwards:

```console
aws ec2 create-security-group --group-name coder-debug --description "temporary SSH" --vpc-id <vpc>
aws ec2 authorize-security-group-ingress --group-id <sg> --protocol tcp --port 22 --cidr <your-ip>/32
aws ec2 modify-instance-attribute --instance-id <id> --groups <sg>
```

### Private flake repositories

Nix fetches flakes as root via the daemon, so credentials must be readable by root rather than by
the workspace user. Prefer `nix.settings.netrc-file` pointing at a file the boot script writes at
mode 0600, or an `!include` of a private file from `/etc/nix/nix.conf`. Do **not** put a token in
`nix.settings.access-tokens` directly: that renders it into `/etc/nix/nix.conf` by way of the Nix
store, where every process on the workspace can read it.

## Extending the template

Three registry modules are included:
[code-server](https://registry.coder.com/modules/coder/code-server),
[jetbrains-gateway](https://registry.coder.com/modules/coder/jetbrains-gateway) and
[git-config](https://registry.coder.com/modules/coder/git-config).

The first two push a dynamically linked binary into the workspace and exec it, so they work only
because the reference flake sets `programs.nix-ld.enable = true` — remove that and both fail with a
misleading "No such file or directory". Gateway is also told which architecture to fetch, from the
same instance-type map that picks the AMI, and is restricted to the IDEs JetBrains publishes an
`aarch64` backend for.

> [!NOTE]
> A registry module whose script starts with `#!/bin/bash` cannot run here. NixOS puts nothing in
> `/bin` but `sh`, so the kernel fails the exec before anything runs and the agent reports exit
> 255 with an empty log. `#!/usr/bin/env bash` works. Check the module before adding it.

The `coder` CLI itself is put on `PATH` by the flake's Coder module, which the `coder stat`
metadata scripts depend on. The agent prepends its own directory to the `PATH` it hands scripts,
but on NixOS those run through a login shell and `/etc/profile` rebuilds `PATH` from the system
environment, dropping it — so without that wrapper every CPU/memory/disk metric reads
`coder: command not found`.

For anything heavier, prefer declaring the tool in your flake and exposing it with a
[`coder_app`](https://registry.terraform.io/providers/coder/coder/latest/docs/resources/app):
it is reproducible and avoids the dynamic-linking problem entirely.

The template is two halves that do not know about each other:

- [`modules/amazon-init/`](./modules/amazon-init/README.md) gets Coder onto an EC2 instance whose
  AMI runs `amazon-init` instead of cloud-init. It publishes the agent handoff and the workspace
  identity, streams logs before an agent exists, runs one script, and starts the agent last.
  Nothing in it mentions Nix — the script it runs is an opaque string.
- [`modules/nix/`](./modules/nix/README.md) is the flake lifecycle: sync a checkout, decide whether
  a rebuild is needed, apply it, filter the output. Nothing in it mentions EC2 or user-data.

`scripts/boot.sh.tftpl` is the seam: it is handed to the first as `boot_script` and uses the
second. Either half can be lifted into a standalone registry module without untangling it from the
other.
