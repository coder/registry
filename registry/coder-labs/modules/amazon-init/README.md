---
display_name: amazon-init
description: Start the Coder agent from EC2 user-data run by amazon-init on NixOS
icon: ../../../../.icons/aws.svg
verified: false
tags: [helper, aws, ec2, nixos]
---

# amazon-init

Render EC2 user-data that NixOS's `amazon-init.service` runs on every boot. It
writes the agent handoff and public facts, runs `boot_script` as root, then
starts the agent even on failure. Do not enable the agent unit at boot.

```tf
module "amazon-init" {
  source            = "registry.coder.com/coder-labs/amazon-init/coder"
  version           = "1.0.0"
  agent_token       = coder_agent.main.token
  agent_init_script = coder_agent.main.init_script
  boot_script       = local.my_boot_script
}
```

Pass the result to the instance with `user_data = module.amazon-init.user_data`
on an `aws_instance`, and set `user_data_replace_on_change = false` so rotating
the token does not replace the root disk. The
[aws-nixos template](../../templates/aws-nixos) pairs this module with the
[Nix(OS) module](../nix)'s `boot_script`.

`runtime_dir` must be tmpfs. Root-owned scripts cannot be replaced by the agent;
only `agent.env` (0600) and `init.sh` (0700) pass to it. The token also lives in
Terraform state and EC2 user-data: restrict IMDS access. Never put secrets in
public `values` or `files` (0644).

The root boot script receives `CODER_RUNTIME_DIR`, `CODER_WORKSPACE_FACTS`,
`CODER_ACCESS_URL`, `CODER_AGENT_TOKEN`, `CODER_LOG_SOURCE_ID`, and `CODER_LOG_LIBRARY`.
Early logs require outbound Coder access and `curl`. The shared 1 MiB
agent log cap is budgeted. `files` paths are trusted admin input: do not
write into `runtime_dir` or through symlinked directories.
