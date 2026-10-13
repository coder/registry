---
display_name: Nix(OS)
description: Apply a NixOS flake on boot and open nix develop shells in Coder workspaces
icon: ../../../../.icons/nixos-rainbow.svg
verified: false
tags: [helper, nix, nixos]
---

# Nix(OS)

Use Nix in a Coder workspace in two independent ways; enable either or both. **`nixos`** (on by default) renders a root-run `boot_script` that clones a Git flake and runs `nixos-rebuild switch` before the agent starts. **`develop`** enters a project's `nix develop` shell, optionally as a one-click terminal app.

```tf
module "nix" {
  source   = "registry.coder.com/coder-labs/nix/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  nixos = {
    flake_ref  = "git+https://github.com/coder/nixos-example-flake?ref=main"
    flake_attr = "coder-workspace-ec2-$ARCH"
    arch       = "x86_64"
  }

  develop = {
    enabled = true
    path    = "~/project"
  }
}
```

## NixOS

`nixos` produces a script, not a resource: hand `module.nix.boot_script` to whatever runs a script on every boot (cloud-init, EC2 user-data, a systemd unit) before the agent starts. See the [AWS EC2 (NixOS) template](../../templates/aws-nixos) for a complete example that wires it into EC2 user-data. Configurations come from a flake (`type = "flake"`, the only supported type today; channels may follow).

References accept HTTP(S) or SSH Git URLs, with an optional `git+` prefix and `?ref=` branch. Without `ref`, Git follows the remote's default branch. `github:` shorthands, fragments, and other query parameters such as `?dir=` are rejected. `$ARCH` in `flake_attr` expands to `arch` (`x86_64` or `aarch64`), so one template can offer paired hosts per architecture. HTTP URL userinfo is allowed for private clones, but it leaks into the checkout's `.git/config`, Terraform state, and the `flake_uri` output; prefer root-managed Git credentials.

The script expects root, systemd, NixOS, and outbound access to Git and the Nix caches your flake uses. It runs before the agent exists, so its directories (`/etc/nixos`, `/var/lib/coder-nixos`, `/var/log/coder-nixos` by default) are system paths rather than per-user module directories.

- A clean checkout fast-forwards to the remote. Tracked edits and local commits are left untouched, so the configuration can be edited in place.
- Untracked files never trigger a rebuild, because Git flakes ignore them.
- The last built revision and attribute are recorded in `state_dir`. A lock there serialises rebuilds with any other caller that takes it.
- Each rebuild writes a transcript to `log_dir`, with `rebuild-latest.log` pointing at the newest one. A failed rebuild leaves the previous generation active and exits non-zero; the caller should still start the agent so the workspace stays reachable.

If the caller provides `CODER_LOG_LIBRARY` (a shell library defining `coder_log` helpers), the script streams progress through it, for example to a Coder agent log source. Otherwise it falls back to plain output. `version_command` is a shell snippet for a `coder_agent` `metadata` block that reports the running NixOS version and flags a generation that is staged but not yet booted.

## nix develop

With `develop.enabled`, the module adds a **Nix Develop** terminal app to the agent. The app changes into `develop.path` and runs `nix develop` there, with `nix-command` and `flakes` enabled. `path` and `agent_id` are required. Relative paths and `~/` resolve from the workspace user's home directory. Set `shell` to pick a `devShells` attribute other than the default:

```tf
module "nix" {
  source   = "registry.coder.com/coder-labs/nix/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  nixos = { enabled = false }

  develop = {
    enabled = true
    path    = "/home/coder/project"
    shell   = "ci"
  }
}
```

`nix` must already be installed, as it is on NixOS; this module does not install Nix. The project must contain a committed or tracked `flake.nix`. The `develop_command` output holds the app's command, for reuse in your own apps or scripts.

### Prebuilding dev shells

By default (`prebuild = true`), a script runs `nix develop --profile … --command true` in the project when the workspace starts. This fetches or builds everything the dev shell needs before you open it. The script waits up to 10 minutes for `flake.nix` to appear, so a repository cloned by another module at startup is picked up. The resulting environment is recorded as a profile under `~/.coder-modules/coder-labs/nix/develop/`. That profile is a garbage-collector root, so `nix-collect-garbage` keeps the dependencies. The app updates the same profile every time it opens.

The prebuild doesn't block login. If it fails, the app builds on first use instead. Logs are in `~/.coder-modules/coder-labs/nix/logs/install.log`. The `scripts` output lists the script's `coder exp sync` name, so other scripts can wait for it.

## Nix settings

On NixOS, put Nix settings in your flake's `nix.settings` if you control the flake. They're declarative, versioned with the system, checked at build time, and apply to everyone:

```nix
{
  nix.settings = {
    extra-substituters        = [ "https://cache.example.org?priority=30" ];
    extra-trusted-public-keys = [ "cache.example.org-1:AbC...=" ];
  };
}
```

Use the module's `config` when you can't change the flake, for example to add an organization's binary cache under flakes your users bring themselves. Also use it for values that come from Terraform, and with `develop` on hosts that aren't NixOS:

```tf
module "nix" {
  source  = "registry.coder.com/coder-labs/nix/coder"
  version = "1.0.0"

  config = {
    extra-substituters        = ["https://cache.example.org?priority=30"]
    extra-trusted-public-keys = ["cache.example.org-1:AbC...="]
  }

  nixos = {
    flake_ref  = "https://github.com/coder/nixos-example-flake"
    flake_attr = "coder-workspace-ec2-$ARCH"
  }
}
```

`config` is shared by both modes. `nixos.config_override` and `develop.config_override` replace individual keys for one mode. Lists are joined with spaces, and booleans become `true`/`false`. The module never edits `/etc/nix/nix.conf` (generated by NixOS) or `~/.config/nix/nix.conf` (often generated by home-manager). Its settings are layered on top, after those files. Prefer `extra-*` keys: they add to the values configured there, while a plain key such as `substituters` replaces them.

- **NixOS:** the boot script writes the settings to `/run/coder-nixos/nix.conf` on every boot, so removing them from Terraform removes them on the next boot. It also appends one `!include` line for that file to root's `/root/.config/nix/nix.conf`, then restarts `nix-daemon` when anything changed. Every root Nix process reads that config: the boot rebuild, a later `sudo nixos-rebuild`, and the daemon, which builds and downloads for all users, `nix develop` included. Normal users don't read it. If root's config is a read-only symlink (e.g. home-manager for root), the script leaves it alone and applies the settings to the boot rebuild only. `sudo -E` with your own `XDG_CONFIG_HOME` exported makes root read your config instead of root's.
- **develop:** the settings are exported workspace-wide as `NIX_CONFIG` (`export_config = true`, the default), so a `nix develop` you run by hand gets them too. With `export_config = false`, only the app and the prebuild append them to their own `NIX_CONFIG`. When `nixos` is enabled, the `trusted-public-keys`, `trusted-substituters` and `trusted-users` keys (and their `extra-` forms) are left out. The daemon already has them, and an untrusted user sending them again only gets "ignoring the client-specified setting" warnings.

The Nix daemon only uses a substituter requested by a normal user if it's in the daemon's `trusted-substituters`, or if the user is in `trusted-users`. On NixOS, put caches in `config` or `nixos.config_override` so the daemon has them. On other hosts, `develop` settings work with single-user Nix installs and for trusted users. A project flake's own `nixConfig` only applies with `accept-flake-config = true`, which you can set in `develop.config_override`.

To check the result, run `sudo nix config show` (root and the daemon) or `nix config show` (your user). Older Nix versions call it `nix show-config`.
