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

## Examples

### Stream boot-script output to the workspace

The boot script can source `CODER_LOG_LIBRARY` to write to the workspace's build
log before the agent is up. `coder_log` sends one line and `coder_log_pipe`
forwards a command's output, both tagged with a level.

```tf
module "amazon-init" {
  source            = "registry.coder.com/coder-labs/amazon-init/coder"
  version           = "1.0.0"
  agent_token       = coder_agent.main.token
  agent_init_script = coder_agent.main.init_script

  log_display_name = "Provisioning"
  log_icon         = "/icon/aws.svg"
  boot_script      = <<-EOT
    . "$CODER_LOG_LIBRARY"
    coder_log info "Preparing the workspace disk"
    systemctl restart my-service 2>&1 | coder_log_pipe info
  EOT
}
```

### Ship files and workspace facts

`files` writes small files (mode 0644) before the boot script runs. `values` adds
public keys to `workspace.json`, which services can read at runtime.

```tf
module "amazon-init" {
  source            = "registry.coder.com/coder-labs/amazon-init/coder"
  version           = "1.0.0"
  agent_token       = coder_agent.main.token
  agent_init_script = coder_agent.main.init_script

  files = {
    "/etc/motd" = "Welcome to ${data.coder_workspace.me.name}"
  }
  values = {
    region = "eu-west-3"
  }
  boot_script = <<-EOT
    jq -r .region "$CODER_WORKSPACE_FACTS" > /etc/workspace-region
  EOT
}
```

### Override host and runtime settings

The hostname defaults to the workspace name. `runtime_dir` must stay on a
tmpfs. `path` is prepended to the boot script's `PATH` (the default suits NixOS).
Lower `log_budget_bytes` if other log sources need more of the agent's 1 MiB log cap.

```tf
module "amazon-init" {
  source            = "registry.coder.com/coder-labs/amazon-init/coder"
  version           = "1.0.0"
  agent_token       = coder_agent.main.token
  agent_init_script = coder_agent.main.init_script
  boot_script       = local.my_boot_script

  hostname         = "dev-box"
  runtime_dir      = "/run/my-coder"
  path             = "/usr/local/bin"
  log_budget_bytes = 131072
}
```

## Security

`runtime_dir` must be tmpfs. Root-owned scripts cannot be replaced by the agent;
only `agent.env` (0600) and `init.sh` (0700) pass to it. The token also lives in
Terraform state and EC2 user-data: restrict IMDS access. Never put secrets in
public `values` or `files` (0644).

The root boot script receives `CODER_RUNTIME_DIR`, `CODER_WORKSPACE_FACTS`,
`CODER_ACCESS_URL`, `CODER_AGENT_TOKEN`, `CODER_LOG_SOURCE_ID`, and `CODER_LOG_LIBRARY`.
`files` paths are trusted admin input: do not write into `runtime_dir` or
through symlinked directories.

## Privileges

`amazon-init.service` runs user-data as root, so this module needs root and has
no unprivileged mode. It writes to `runtime_dir`, sets the hostname, runs
`boot_script`, and starts `coder-agent.service` with `systemctl`. The agent
itself runs as the unit's `User=`, which gets only `agent.env`, `init.sh`,
and `runtime_dir/bin`.

## Network access

The module downloads and installs nothing. These are the only endpoints it
contacts:

| When               | Endpoint                                                    | Purpose                             |
| ------------------ | ----------------------------------------------------------- | ----------------------------------- |
| Boot, via EC2      | Instance metadata service (`169.254.169.254`)               | `amazon-init` fetches the user-data |
| Boot, before agent | `POST <access_url>/api/v2/workspaceagents/me/log-source`    | Register the boot log source        |
| Boot, before agent | `PATCH <access_url>/api/v2/workspaceagents/me/logs`         | Stream boot logs, capped by budget  |
| Agent start        | Whatever `agent_init_script` uses (normally `<access_url>`) | Download and run the Coder agent    |

In restricted or air-gapped networks, the instance only needs to reach the
Coder access URL. Your `boot_script` may reach other endpoints. Logging is
best-effort and needs `curl`. Without `curl`, the module skips early logs and
continues. If the access URL is unreachable, the module retries the log-source
registration for up to 10 minutes before it runs the boot script.
