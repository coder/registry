# Nix flake lifecycle

`lifecycle.sh.tftpl` is the only part of this template that knows about Nix.
It is kept separate so it can be lifted into a standalone Coder registry
module without untangling it from EC2 and Coder specifics first.

## Contract

Inputs are environment variables, set by the caller:

| Variable         | Meaning                                        |
| ---------------- | ---------------------------------------------- |
| `NIX_FLAKE_DIR`  | checkout to sync and build (e.g. `/etc/nixos`) |
| `NIX_FLAKE_ATTR` | `nixosConfigurations` attribute                |
| `NIX_STATE_DIR`  | revision marker and lock file                  |
| `NIX_LOG_DIR`    | transcripts                                    |

Output goes through a `nix_log <level> <message>` function that the caller
may define; it falls back to stdout. That hook is the only coupling to
Coder, and it is one function.

| Function                                | Responsibility                                  |
| --------------------------------------- | ----------------------------------------------- |
| `nix_sync_checkout <ref> <branch>`      | clone, fast-forward, or leave local work alone  |
| `nix_needs_rebuild`                     | echo the revision, return 0 when work is needed |
| `nix_apply <switch\|boot> <transcript>` | build and apply                                 |
| `nix_record_rev <rev>`                  | record what was applied                         |
| `nix_pending_generation`                | true when a generation is staged but not booted |
| `nix_filter_log`                        | drop noise from nix's output                    |
| `nix_lock [nowait]`                     | serialise concurrent callers                    |

## Where this is going

The eventual `registry/coder/modules/nix/` should manage a flake lifecycle on
any Linux host, not only NixOS: `nix develop`, `nix profile`, devshells, with
`nixos-rebuild` as one backend among several.

That is why the split is **resolve → decide → apply**, and why `nix_apply` is
a single function. It is the only NixOS-specific piece, so a `nix develop`
backend becomes a sibling of it rather than a rewrite. `nix_flake_rev`,
`nix_needs_rebuild`, `nix_filter_log` and `nix_lock` are already
platform-agnostic.

No Terraform module is published yet; this is structure and documentation.

## Two invariants worth not breaking

**Nothing is injected at evaluation time.** The commands this module runs are
exactly what a user can type by hand -- no `--override-input`, no `--impure`,
no `--no-write-lock-file`. That is deliberate: the template does not control
the flake, and a rebuild that only works with special flags is a rebuild the
user cannot reproduce. Facts about the workspace are exposed as a runtime
JSON file instead, and the agent token lives in a tmpfs file at mode 0600.
Do not "simplify" either into a flake input -- anything Nix sees is
world-readable in the store and persists across generations.

**Local work is never discarded.** `nix_sync_checkout` fast-forwards only a
clean checkout on its tracking branch; a dirty tree or local commits are
built as they are.

**Logging is best-effort.** A failure to report progress must never abort a
rebuild. `nix_log` failures are swallowed by the caller.
