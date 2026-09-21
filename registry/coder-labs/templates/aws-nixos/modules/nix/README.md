# nix

The flake lifecycle: keep a checkout in sync with a Git remote, decide whether
the running system is out of date, and rebuild it.

Nothing here knows about EC2, user-data, or how the instance came to exist.
The boot path is a **string** the caller hands to whatever runs scripts on the
machine, and the periodic rebuild is an ordinary `coder_script`. On AWS the
caller is [`../amazon-init`](../amazon-init/README.md), but nothing depends on
that.

```tf
module "nix" {
  source = "./modules/nix"

  agent_id  = try(coder_agent.main[0].id, "")
  flake_ref = "git+https://github.com/coder/nixos-example-flake?ref=main"
  arch      = "x86_64"
}
```

## The flake reference

One string, in the form `nix` itself accepts. `?ref=` carries the branch, and
without it the remote's default branch is used — resolved on the instance,
since Terraform cannot know it without talking to the remote.

| `flake_ref`                           | builds          |
| ------------------------------------- | --------------- |
| `https://host/org/repo`               | default branch  |
| `git+https://host/org/repo?ref=dev`   | `dev`           |
| `git+ssh://git@host/org/repo?ref=dev` | `dev`, over SSH |

`$ARCH` in `flake_attr` is replaced with `arch`, so one template can offer both
architectures without the attribute and the machine disagreeing.

## What runs where

`boot_script` runs as root on every boot, before the agent is started. It syncs
the checkout, and rebuilds only if the configuration changed:

- a **clean** checkout is fast-forwarded to the remote
- a **dirty** one, or one carrying local commits, is left alone and built as it
  is — someone is working on it
- a checkout on a different branch than requested says so rather than silently
  building the wrong thing

The `coder_script` does the same later, on `update_schedule`, with
`update_process = boot` (stage for the next restart) or `switch` (apply now).
A `flock` in `state_dir` keeps the two from overlapping; the scheduled run
skips rather than queues.

## Logging

`scripts/lifecycle.sh` sends output through a single `nix_log <level> <message>`
hook. Define it and progress goes wherever you want; leave it undefined and it
prints to stdout.

`boot_script` sets that hook up from `CODER_LOG_LIBRARY` when the bootstrapper
provides one — that is how output reaches the workspace UI before an agent
exists — and falls back to plain `echo` when it does not.

Raw `nix` output is filtered before it is logged: store-path lists,
per-derivation build output and lock-file noise are dropped, and list headers
that promised a list are rewritten as sentences. Transcripts in `log_dir` keep
everything, unfiltered.

## Inputs and outputs

`flake_dir`, `state_dir` and `log_dir` default to `/etc/nixos`,
`/var/lib/coder-nixos` and `/var/log/coder-nixos`, and both scripts take them
from here — the paths are defined once.

Outputs exist for the things a caller genuinely cannot do itself:
`boot_script`, `flake_uri` and `flake_attr` for display, `log_dir` and
`flake_dir` for pointing people at, and `version_command` for a `coder_agent`
metadata block — which has to be declared inline on the agent, though what it
means for a NixOS machine to be up to date does not belong in a template.

## Moving this to the registry

It is a self-contained Terraform module already. Publishing it as
`registry.coder.com/coder/nix` needs `.tftest.hcl` coverage and a decision
about `nixos-rebuild` on non-NixOS hosts (`nix profile` would be the
equivalent), not untangling.
