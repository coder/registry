---
display_name: Nix(OS)
description: Apply a NixOS flake to the workspace on every boot, before the Coder agent starts
icon: ../../../../.icons/nixos-rainbow.svg
verified: false
tags: [helper, nix, nixos]
---

# Nix(OS)

Render a root-run `boot_script` that clones a Git flake and runs `nixos-rebuild switch` when the checkout, attribute, or active generation changes. The module creates no resources: hand `boot_script` to whatever runs a script on every boot (cloud-init, EC2 user-data, a systemd unit) before the agent starts. `type = "nixos"` is the only supported mode today; a `nix develop` mode (`type = "develop"`) is planned.

```tf
module "nix" {
  source     = "registry.coder.com/coder-labs/nix/coder"
  version    = "1.0.0"
  type       = "nixos"
  flake_ref  = "git+https://github.com/coder/nixos-example-flake?ref=main"
  flake_attr = "coder-workspace-ec2-$ARCH"
  arch       = "x86_64"
}

# e.g. as part of the instance's user-data
locals {
  user_data = module.nix.boot_script
}
```

See the [AWS EC2 (NixOS) template](../../templates/aws-nixos) for a complete example that wires `boot_script` into EC2 user-data alongside the Coder agent.

## Flake references

References accept HTTP(S) or SSH Git URLs, with an optional `git+` prefix and `?ref=` branch. Without `ref`, Git follows the remote's default branch. `github:` shorthands, fragments, and other query parameters such as `?dir=` are rejected. `$ARCH` in `flake_attr` expands to `arch` (`x86_64` or `aarch64`), so one template can offer paired hosts per architecture.

HTTP URL userinfo is allowed for private clones, but it leaks into the checkout's `.git/config`, Terraform state, and the `flake_uri` output. Prefer root-managed Git credentials.

## Boot script behaviour

The script expects root, systemd, NixOS, and outbound access to Git and the Nix caches/inputs your flake uses. It runs before the agent exists, so its directories (`/etc/nixos`, `/var/lib/coder-nixos`, `/var/log/coder-nixos` by default) are system paths rather than per-user module directories.

- A clean checkout fast-forwards to the remote. Tracked edits and local commits are left untouched, so the configuration can be edited in place.
- Untracked files never trigger a rebuild, because Git flakes ignore them.
- The last built revision and attribute are recorded in `state_dir`. A lock there serialises rebuilds with any other caller that takes it.
- Each rebuild writes a transcript to `log_dir`, with `rebuild-latest.log` pointing at the newest one. A failed rebuild leaves the previous generation active and exits non-zero; the caller should still start the agent so the workspace stays reachable.

If the caller provides `CODER_LOG_LIBRARY` (a shell library defining `coder_log` helpers), the script streams progress through it, for example to a Coder agent log source. Otherwise it falls back to plain output.

`version_command` is a shell snippet for a `coder_agent` `metadata` block. It reports the running NixOS version and flags a generation that is staged but not yet booted.
