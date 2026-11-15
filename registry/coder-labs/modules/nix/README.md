---
display_name: Nix(OS)
description: Build a workspace from a NixOS flake on boot and/or open nix develop shells
icon: ../../../../.icons/nixos-rainbow.svg
verified: true
tags: [helper, nix, nixos]
---

# Nix(OS)

Apply a NixOS flake before the agent starts, open a project's `nix develop` shell, or do both. At least one mode must be enabled. Nix must already be installed; this module does not install Nix or Lix.

```tf
module "nix" {
  source   = "registry.coder.com/coder-labs/nix/coder"
  version  = "2.0.1"
  agent_id = coder_agent.main.id

  nixos = {
    flake_ref   = "https://github.com/coder/nixos-example-flake?ref=main"
    flake_attr  = "coder-workspace-ec2-x86_64"
    agent_token = try(coder_agent.main[0].token, "")
    arch        = "amd64"
  }
  develop = {
    enabled = true
    path    = "~/project"
  }
}
```

## NixOS

NixOS mode adds a root **builder** agent, shown after the main agent. Its **NixOS rebuild** script clones the Git repository, runs `nixos-rebuild switch`, and then starts the main agent's `coder-agent.service`. If the rebuild fails, the main agent stays stopped and the builder keeps a root shell to fix it: `coder ssh <workspace>.builder`. Run `systemctl restart coder-builder` there, or restart the workspace, to try again. The builder's **Rebuild status** shows `running`, `ok` or `failed (exit N)`, since the dashboard keeps a connected agent green even when its startup script fails. The builder stays connected because Coder marks a workspace unhealthy when any agent disconnects. With two agents, CLI commands must name one, e.g. `coder ssh <workspace>.main`.

Pass the main agent's token as `agent_token` and the instance's agent architecture as `arch`. The main agent must use `auth = "token"` and the same architecture, because it runs the builder's init script. Hand the sensitive `boot_script` output to cloud-init, EC2 user-data, or another hook that runs it as root on every boot; see the [AWS EC2 (NixOS) template](../../templates/aws-nixos) for complete wiring. It needs the `coder-agent.service` handoff from the [Coder NixOS modules](https://github.com/coder/nixos-modules) in `runtime_dir`, and passes its own environment to the builder, so `git` must be on the hook's `PATH`. A `git+` URL prefix and `?ref=` branch are supported; otherwise Git uses the default branch.

A new checkout adopts the target directory: files tracked by the flake take precedence; unrelated files are kept. Subsequent boots fast-forward clean checkouts only. Tracked edits and local commits are preserved, and a checkout pointing to another repository is built as-is with a warning. Untracked files don't trigger rebuilds because Git flakes ignore them.

Rebuild transcripts are written to `/var/log/coder-nixos/rebuild-latest.log`, next to the builder agent's own logs. The builder's log stops at 512 KiB, below Coder's 1 MiB per-agent cap; the transcript keeps the rest. The last built revision is recorded in `/var/lib/coder-nixos`. These are system paths so the workspace user can read the logs; development scripts use the standard per-user module directory.

Credentials embedded in Git URLs appear in Terraform state, the checkout's `.git/config` and `flake_uri`; prefer externally managed Git credentials.

## nix develop

Enabling `develop` adds a **Nix Develop** terminal app. It requires `path` and `agent_id`; `shell` selects a dev shell other than the default. `path` is inserted as shell syntax, so `~/project` and `$HOME/project` work; quote paths containing spaces, e.g. `path = "\"$HOME/my project\""`.

For a workspace that isn't NixOS:

```tf
module "nix" {
  source   = "registry.coder.com/coder-labs/nix/coder"
  version  = "2.0.1"
  agent_id = coder_agent.main.id
  nixos    = { enabled = false }
  develop  = { enabled = true, path = "~/project", shell = "ci" }
}
```

The module appends the default Nix profile `bin` directories to the workspace `PATH` through `coder_env`. Apps, startup scripts and manual commands use the same PATH and `NIX_CONFIG`; a custom PATH set directly on `coder_agent` must include the Nix directories itself. Coder provider 2.15 or later is required.

With `prebuild = true` (the default), startup waits up to 10 minutes for the project's `flake.nix` (and, in a Git checkout, its index entry), then runs `nix develop --profile … --command true` to fetch or build the environment. The profile under `~/.coder-modules/coder-labs/nix/develop/` is a GC root shared with the app, so dependencies survive garbage collection. The prebuild doesn't block login; failure logs a warning and the app builds on first use. See `~/.coder-modules/coder-labs/nix/logs/install.log`. Other scripts can use the `scripts` sync names to wait for the prebuild attempt to finish.

## Nix settings

On NixOS, prefer the flake's `nix.settings` for persistent system-wide configuration:

```nix
{
  nix.settings = {
    extra-substituters = [ "https://cache.example.org" ];
    extra-trusted-public-keys = [ "cache.example.org-1:AbC...=" ];
  };
}
```

When you don't control the flake, or for development on another host, pass settings through Terraform:

```tf
# Inside the module block:
config = {
  extra-substituters        = ["https://cache.example.org"]
  extra-trusted-public-keys = ["cache.example.org-1:AbC...="]
}
```

Each mode merges `config` with its `config_override`, replacing individual keys. Lists are space-joined; booleans become `true`/`false`. Prefer `extra-*` settings to append to existing values. Both modes append `extra-experimental-features = nix-command flakes`.

For NixOS, settings are exported as `NIX_CONFIG` for the **boot rebuild only**. They aren't written to any config file and don't configure the daemon or a later `sudo nixos-rebuild`. For development, `NIX_CONFIG` is exported workspace-wide, so manual `nix` commands get the same settings as the app and prebuild. It replaces any other agent-level `NIX_CONFIG`.

On multi-user Nix, an untrusted user's client cannot add new cache trust: configure the substituter and its key in the daemon's configuration (on NixOS, in `nix.settings`). Client settings work directly with single-user Nix or trusted users. A project's `nixConfig` additionally requires accepting the flake configuration.
