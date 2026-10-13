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

`nixos` produces a script, not a resource: hand `module.nix.boot_script` to whatever runs a script on every boot (cloud-init, EC2 user-data, a systemd unit) before the agent starts. See the [AWS EC2 (NixOS) template](../../templates/aws-nixos) for a complete example that wires it into EC2 user-data. Configurations come from a flake.

References accept HTTP(S) or SSH Git URLs, with an optional `git+` prefix and `?ref=` branch. Without `ref`, Git follows the remote's default branch. `github:` shorthands, fragments, and other query parameters such as `?dir=` are rejected. `$ARCH` in `flake_attr` expands to `arch` (`x86_64` or `aarch64`), so one template can offer paired hosts per architecture. HTTP URL userinfo is allowed for private clones, but it leaks into the checkout's `.git/config`, Terraform state, and the `flake_uri` output; prefer root-managed Git credentials.

The script expects root, systemd, NixOS, and outbound access to Git and the Nix caches your flake uses. It runs before the agent exists, so its directories (`/etc/nixos`, `/var/lib/coder-nixos`, `/var/log/coder-nixos` by default) are system paths rather than per-user module directories. They must be canonical absolute paths other than `/`. This is a deliberate exception to the registry's `~/.coder-modules` layout: the workspace user has to be able to read `rebuild-latest.log` and take the same rebuild lock, which wouldn't work under `/root`. The `develop` side does follow the layout.

- A clean checkout fast-forwards to the remote. Tracked edits and local commits are left untouched, so the configuration can be edited in place.
- If `flake_ref` points to a different repository, a checkout with no local changes or unpushed commits is re-cloned from it. One with local work is kept as it is, with a warning.
- Untracked files never trigger a rebuild, because Git flakes ignore them.
- The last built revision and attribute are recorded in `state_dir`. A lock there serialises rebuilds with any other caller that takes it.
- Each rebuild writes a transcript to `log_dir`, with `rebuild-latest.log` pointing at the newest one. A failed rebuild leaves the previous generation active and exits non-zero; the caller should still start the agent so the workspace stays reachable.

If the caller provides `CODER_LOG_LIBRARY` (a shell library defining `coder_log` helpers), the script streams progress through it, for example to a Coder agent log source. Otherwise it falls back to plain output. `version_command` is a shell snippet for a `coder_agent` `metadata` block that reports the running NixOS version and flags a generation that is staged but not yet booted.

## nix develop

With `develop.enabled`, the module adds a **Nix Develop** terminal app to the agent. The app changes into `develop.path` and runs `nix develop` there, with `nix-command` and `flakes` enabled. `path` and `agent_id` are required. `path` is inserted into the app and prebuild scripts as written, as shell: `~/project` and `$HOME/project` both work, and a path with spaces needs quoting, e.g. `"\"$HOME/my project\""`. Set `shell` to pick a `devShells` attribute other than the default, and `slug` to change the app's slug (`nix-develop`):

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

The app runs under Bash, whatever the user's login shell is. `nix` must already be installed, as it is on NixOS; this module does not install Nix. If `nix` is only on the `PATH` in login shells (single-user or multi-user installs on other distributions), the app and prebuild source the Nix profile script themselves. The project must contain a committed or tracked `flake.nix`. The `develop_command` output holds the app's command, for reuse in your own apps or scripts.

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

`config` is shared by both modes. `nixos.config_override` and `develop.config_override` replace individual keys for one mode. Lists are joined with spaces, and booleans become `true`/`false`. Both rendered configs always end up with `nix-command` and `flakes` added to `extra-experimental-features`, after any features you list. The module never edits `/etc/nix/nix.conf` (generated by NixOS) or `~/.config/nix/nix.conf` (often generated by home-manager). Its settings are layered on top, after those files. Prefer `extra-*` keys: they add to the values configured there, while a plain key such as `substituters` replaces them.

- **NixOS:** the boot script writes the settings to `/run/coder-nixos/nix.conf` on every boot, so removing them from Terraform removes them on the next boot. It also appends one `!include` line for that file to root's `/root/.config/nix/nix.conf`, then restarts `nix-daemon` when anything changed. With Nix's default config lookup, root's Nix processes read that file: the boot rebuild, a later `sudo nixos-rebuild`, and the daemon, which builds and downloads for all users, `nix develop` included. Normal users don't read it. The lookup can be redirected by `NIX_USER_CONF_FILES`, `XDG_CONFIG_HOME` or `NIX_CONFIG_HOME` (Nix only, not Lix), for example through `sudo -E` or the daemon's service environment. Root then reads a different file, and the boot script logs a warning when it finds these set at boot or on `nix-daemon.service`. If root's config is a read-only symlink (e.g. home-manager for root), the script leaves it alone and applies the settings to the boot rebuild only.
- **develop:** the settings are exported workspace-wide as `NIX_CONFIG` (`export_config = true`, the default), so a `nix develop` you run by hand gets them too. With `export_config = false`, only the app and the prebuild append them to their own `NIX_CONFIG`. When `nixos` is enabled, the `trusted-public-keys`, `trusted-substituters` and `trusted-users` keys (and their `extra-` forms) are left out. The daemon already has them, and an untrusted user sending them again only gets "ignoring the client-specified setting" warnings.

The Nix daemon only uses a substituter requested by a normal user if it's in the daemon's `trusted-substituters`, or if the user is in `trusted-users`. On NixOS, put caches in `config` or `nixos.config_override` so the daemon has them. On other hosts, `develop` settings work with single-user Nix installs and for trusted users. A project flake's own `nixConfig` only applies with `accept-flake-config = true`, which you can set in `develop.config_override`.

To check the result, run `nix config show` as your user (`nix show-config` on older Nix), or `sudo nix config show` for what root's commands such as `sudo nixos-rebuild` see. Neither shows the running daemon's settings. To check those, build or fetch something as a normal user and look for downloads from your cache, and check that `systemctl show nix-daemon -p Environment` doesn't redirect the config lookup.
