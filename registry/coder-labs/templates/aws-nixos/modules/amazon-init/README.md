# amazon-init

Coder on an EC2 AMI that runs `amazon-init` instead of cloud-init.

It renders user-data that publishes the agent handoff, publishes the
workspace's identity, runs **one script you supply**, and then starts the
agent. It does not know or care what that script does — `boot_script` is an
opaque string, and nothing in this module reads it.

```tf
module "amazon_init" {
  source = "./modules/amazon-init"

  agent_token       = coder_agent.main.token
  agent_init_script = coder_agent.main.init_script
  boot_script       = local.my_boot_script
}

resource "aws_instance" "dev" {
  user_data = module.amazon_init.user_data
}
```

Workspace and owner identity are read from `coder_workspace` and
`coder_workspace_owner` here, so the caller passes neither.

## Why this is not cloud-init

Some AMIs — the official NixOS images among them — do not ship cloud-init.
They run `amazon-init.service`, which reads `/etc/ec2-metadata/user-data` and
execs it as a shell script when it begins with `#!` — after
`multi-user.target`, **on every boot**. There is no `runcmd`, no
`write_files`, no per-boot/once distinction and no ordering hooks. Three
things follow:

- Everything must be idempotent, because it all runs again on every restart.
- It is the only hook available, so the agent handoff, the workspace facts and
  whatever the image needs doing all have to live in it.
- Nothing can be ordered `After` it. A boot script that reconfigures the
  machine may start units synchronously, and `amazon-init` cannot become
  active until it exits — so a unit that waits for `amazon-init` deadlocks the
  first boot.

## Order of operations

1. **Handoff** — `agent.env` (0600), `init.sh`, then `ready`, into
   `runtime_dir` (a tmpfs). Written before anything that can fail, so the
   agent can still be started from a failure path.
2. **Hostname**, from `hostname` or the workspace name.
3. **Logging** — the shell library is written to `$${runtime_dir}/log.sh` and
   sourced, and the log source is registered.
4. **Identity** — `$${runtime_dir}/workspace.json`, mode 0644, no secrets.
5. **Files** — anything in `files`, a map of absolute path to text, written
   mode 0644 with parent directories created.
6. **Your boot script**, as a child process.
7. **The agent**, always, whatever step 6 did.

## Starting the agent last is the point

`coder-agent.service` must not be `wantedBy` anything; this module starts it,
and only once the boot script has finished. Left to systemd, the agent comes
up at `multi-user.target` — before the boot script has finished changing the
machine — reports the workspace ready, and runs its startup scripts against a
system that is about to be replaced under them.

The mirror image of that rule is that a boot script failure must not leave an
unreachable workspace, so the agent is started even when the boot script
exits non-zero. Its status is reported and propagated, never suppressed.

## What the boot script gets

Root, a child process, and these:

| Variable                | Meaning                        |
| ----------------------- | ------------------------------ |
| `CODER_LOG_LIBRARY`     | path to source for `coder_log` |
| `CODER_RUNTIME_DIR`     | the tmpfs this module owns     |
| `CODER_WORKSPACE_FACTS` | path to `workspace.json`       |
| `CODER_ACCESS_URL`      | deployment URL                 |
| `CODER_AGENT_TOKEN`     | agent token                    |
| `CODER_LOG_SOURCE_ID`   | log source to write to         |

The log source is registered before the boot script starts, and `CODER_LOG_READY`
is exported, so sourcing the library is enough — `coder_log` works from the
first line and the boot script must not register the source again.

## Logging before the agent exists

The agent is the normal way to get output into the workspace UI, and on a
first boot it does not exist for as long as the boot script runs. So
`scripts/log.sh` calls the log API directly with the agent's own token:
`coder_log <level> <message>`, `coder_log_pipe <level>` for a stream, and
`coder_log_tail <file> <n>` for the end of a transcript.

The library is internal to this module — it is not an output. On the instance
it is at `$${runtime_dir}/log.sh`, which is where anything the agent runs later
should source it from, and `CODER_LOG_READY` is exported so a process that
sources it does not register the source a second time.

The source id is a `random_uuid` held in Terraform state: stable across
stop/start, new only when the workspace is recreated, by which point the agent
and its logs are new anyway.

Two things it handles that are easy to get wrong:

- **The 1 MiB cap.** Coder caps agent logs at 1 MiB per agent across every
  source. Overflowing does not truncate — the agent is flagged overflowed and
  every later log from every source is dropped permanently. The library tracks
  its own usage and goes quiet at `log_budget_bytes`, which defaults to half
  the cap.
- **No curl.** The image must have one on `PATH` — the NixOS AMI does, in its
  own first generation, before anything has been rebuilt. An image without one
  simply gets no logs: every function here fails closed, because logging must
  never be the reason a boot fails.

## The user-data wrapper

EC2 caps user-data at 16 KiB, and the bootstrap script plus its payloads is
past that. So the output is a six-line self-extracting wrapper around a
gzipped copy.

That is transparent to `amazon-init`: it only checks the first two bytes for
`#!` before exec'ing the blob. The wrapper extracts to
`$${runtime_dir}/bootstrap.sh`, so the real script is on disk when a boot needs
debugging.

The 16 KiB limit is asserted here, as a `precondition` on the `user_data`
output, so the plan fails in the module that decides what goes into user-data
rather than at apply time with an EC2 error that names no cause. Anything
passed through `files` counts against it — and note that those contents are
gzipped before user-data is gzipped again, which buys nothing, so `files` is
for small text.
