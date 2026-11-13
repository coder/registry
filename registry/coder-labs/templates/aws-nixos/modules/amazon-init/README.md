# amazon-init

`amazon-init.service` runs this user-data every boot. It writes the public
workspace facts and `files`, then runs `boot_script` as root with amazon-init's
environment, which has git, nix and nixos-rebuild on `PATH`.

```tf
module "amazon-init" {
  source      = "./modules/amazon-init"
  boot_script = module.nix.boot_script
}
```

`runtime_dir` must be tmpfs: the boot script usually carries agent tokens, and
it also lives in Terraform state and EC2 user-data, so restrict IMDS access.
Never put secrets in public `values` or `files` (0644). `files` paths are
trusted admin input: do not write into `runtime_dir` or through symlinked
directories.
