# amazon-init

`amazon-init.service` runs this user-data every boot. It writes the main agent
handoff and public facts, then starts a root builder agent as the
transient `coder-builder` unit. Do not enable the main agent unit at boot:
the builder prepares the machine and then runs `start_agent_command`,
also after a failure.

```tf
module "amazon-init" {
  source              = "./modules/amazon-init"
  agent_token         = coder_agent.main.token
  agent_init_script   = coder_agent.main.init_script
  builder_token       = coder_agent.builder.token
  builder_init_script = coder_agent.builder.init_script
}

resource "coder_script" "prepare" {
  agent_id     = coder_agent.builder.id
  display_name = "Prepare"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    trap '${module.amazon-init.start_agent_command}' EXIT
    my-setup
  EOT
}
```

The builder agent must stay connected: Coder marks a workspace unhealthy
when any agent disconnects. It writes its logs to `builder_log_dir` and uses
`/var/tmp/coder-builder` as `TMPDIR`, so it leaves the agent defaults in
`/tmp` to the main agent.

`runtime_dir` must be tmpfs. Root-owned scripts cannot be replaced by the agent;
only `agent.env` (0600) and `init.sh` (0700) pass to it. Both tokens also live in
Terraform state and EC2 user-data: restrict IMDS access. Never put secrets in
public `values` or `files` (0644). `files` paths are trusted admin input: do not
write into `runtime_dir` or through symlinked directories.
