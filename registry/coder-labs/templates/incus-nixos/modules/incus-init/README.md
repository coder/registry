# incus-init

The Incus counterpart of [amazon-init](../../../aws-nixos/modules/amazon-init):
stock NixOS images have no hook that runs user-data, so the template runs this
module's launcher through the Incus agent on every start instead.

```tf
resource "incus_instance" "dev" {
  # ...
  exec = {
    "coder-init" = {
      command     = module.incus-init.command
      environment = module.incus-init.environment
    }
  }
}
```

The launcher extracts the bootstrap into `runtime_dir` and detaches it into the
transient `coder-init.service`, so the build is not held open by a long first
rebuild. The bootstrap writes the agent handoff and public facts, runs
`boot_script` as root, then starts the agent even on failure. Do not enable
the agent unit at boot. Follow it with `journalctl -u coder-init`.

`runtime_dir` must be tmpfs. Root-owned scripts cannot be replaced by the agent;
only `agent.env` (0600) and `init.sh` (0700) pass to it. The token travels in
the exec environment, never argv, but also lives in Terraform state: restrict
access to it. Never put secrets in public `values` or `files` (0644).

The root boot script receives `CODER_RUNTIME_DIR`, `CODER_WORKSPACE_FACTS`,
`CODER_ACCESS_URL`, `CODER_AGENT_TOKEN`, `CODER_LOG_SOURCE_ID`, and `CODER_LOG_LIBRARY`.
Early logs require outbound Coder access and `curl`. The shared 1 MiB
agent log cap is budgeted. `files` paths are trusted admin input: do not
write into `runtime_dir` or through symlinked directories.
