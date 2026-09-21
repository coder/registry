# amazon-init

The platform half of this template: everything that is true because the
workspace is a NixOS AMI on EC2, and nothing that is true because it is Nix
(that is [`../nix`](../nix/README.md)) or because it is Coder.

It renders one thing — EC2 user-data — and is the only part of the template
that knows how a NixOS instance is bootstrapped.

## Why this is not cloud-init

The NixOS AMI does not run cloud-init. It runs `amazon-init.service`, which
reads `/etc/ec2-metadata/user-data` and execs it as a shell script when it
begins with `#!` — after `multi-user.target`, **on every boot**. There is no
`runcmd`, no `write_files`, no per-boot/once distinction, and no ordering
hooks. Three things follow, and they shape the whole script:

- It must be idempotent, because it runs again on every restart.
- It is the only hook available, so the agent handoff, the workspace facts and
  the rebuild all have to live in it.
- Nothing can be ordered `After` it. `nixos-rebuild switch` starts new units
  synchronously and `amazon-init` cannot become active until its script exits,
  so a unit that waits for it deadlocks the first boot. This is why the Coder
  agent unit is started _by_ this script rather than wanted by a target.

## What the script does

1. Publishes the agent handoff to `/run/coder` — `agent.env` (0600), `init.sh`,
   then `ready` last — before anything that can fail, so the agent can still be
   started from a failure path.
2. Writes the per-workspace facts to `/run/coder/workspace.json`.
3. Syncs the flake checkout and rebuilds, streaming progress to the workspace
   UI.
4. Starts `coder-agent.service`, and does so on every exit path, including a
   failed rebuild.

## The user-data wrapper

The boot script, its two shell libraries and the agent init script come to
roughly 19 KiB, against EC2's 16 KiB limit. So the user-data this module
outputs is a six-line self-extracting wrapper around a gzipped copy, which
lands at about 9 KiB.

That is transparent to the AMI: `amazon-init` only checks the first two bytes
for `#!` before exec'ing the blob. The wrapper extracts to a fixed path,
`/run/coder/bootstrap.sh`, so the real script is on disk when a boot needs
debugging.

`user_data_bytes` is exported unwrapped so the caller can assert the limit in a
`precondition` — the output itself is sensitive, because the agent token is
inside it, and Terraform suppresses error messages derived from sensitive
values.

## Contract

Inputs are the workspace's identity and the flake to build; the two shell
libraries are passed in as strings rather than read here, so the template's
other entrypoints share one copy. The token is written to a tmpfs at 0600 and
never passed into Nix.
