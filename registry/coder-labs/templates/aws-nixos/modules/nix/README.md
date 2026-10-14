# nix

This local module renders a root-run `boot_script` before the Coder agent starts. It clones a Git flake and runs `nixos-rebuild switch` when the checkout, attribute, or active generation changes.

```tf
module "nix" {
  source     = "./modules/nix"
  flake_ref  = "git+https://github.com/coder/nixos-example-flake?ref=main"
  flake_attr = "coder-workspace-ec2-$ARCH"
  arch       = "x86_64"
}
```

References accept HTTP(S) or SSH Git URLs, optional `git+` and `?ref=`. Without `ref`, Git follows the default branch. `$ARCH` expands to `arch`. HTTP URL userinfo is allowed but leaks into the checkout and `flake_uri` output; prefer root-managed authentication. The instance requires outbound Git and Nix input/substituter access, root privileges, systemd, and NixOS.

A clean checkout fast-forwards; tracked edits and local commits remain untouched. Untracked files do not trigger builds: Git flakes ignore them. The `state_dir` lock prevents races only with callers that take it. Rebuild transcripts live in `log_dir`. First-boot failures may require AWS logs before the agent exists.

The caller runs `boot_script` as root before agent startup. Display outputs include `flake_uri`, `flake_attr`, `flake_dir`, `log_dir` and `version_command`; `values` passes through unchanged.
