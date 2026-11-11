---
display_name: Agent Relay Devin
description: Runs Devin Outposts sessions in Coder workspaces that Agent Relay dispatches.
icon: ../../../../.icons/devin.svg
verified: true
tags: [agent, devin, agent-relay]
---

# Agent Relay Devin

Makes a Coder template a target for [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
Devin pools. Agent Relay claims sessions from a Devin outpost's queue and
dispatches each one to a workspace built from the template; the module
declares the parameters the relay stamps on each build, downloads and
verifies `devin-remote`, and runs `devin-remote serve` for the session.

```tf
module "devin_remote" {
  source   = "registry.coder.com/coder/agent-relay-devin/coder"
  version  = "0.1.0"
  agent_id = coder_agent.main.id
}

resource "coder_agent" "main" {
  # ...
  metadata {
    key          = "agent_relay_status"
    display_name = "Devin remote"
    script       = module.devin_remote.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  metadata {
    key          = "agent_relay_session_attached"
    display_name = "Session attached"
    script       = module.devin_remote.session_attached_metadata_script
    interval     = 30
    timeout      = 5
  }
}
```

Both metadata blocks are required. They have to live on the `coder_agent`,
which the module cannot declare; the relay reads `agent_relay_status` to
decide when to reap the workspace and `agent_relay_session_attached` to keep
its autostop deadline moving.

When Agent Relay stamps an `https://` URL in `agent_relay_devin_session_url`,
the module adds an external **Open in Devin** app that opens the session in
Devin's web app. A workspace a person creates by hand has no session, so no
button is created.

## Requirements

- Coder 2.39.0 or newer. Agent Relay delivers the session's connect token as
  an ephemeral workspace secret, which the agent injects as
  `AGENT_RELAY_DEVIN_TOKEN`. Without it the start step has no token, so the
  workspace only idles.
- A Linux image on `x86_64` or `arm64` with `bash`, `git`, `curl` or `wget`,
  and `sha256sum` (or `shasum`). Devin clones repositories with `git`.
- Optional: `ffmpeg`, Chrome or Chromium (`chrome_path`), and a display
  (`DISPLAY` or `WAYLAND_DISPLAY`, with `desktop = true`) for Devin's browser
  and desktop tools.
- If the workspace user gets passwordless `sudo` so Devin can install what a
  task needs, grant it only on workspaces that serve one session and are
  deleted or recycled afterward.
- Outbound access to `static.devin.ai` for the download, and to the gateway
  URL Devin returns with the claim.

## Connect token

The pool's Devin credentials never leave Agent Relay. When the relay claims a
session, Devin returns a connect token and a gateway URL for it. The relay
sends the token as an ephemeral workspace secret, which the agent injects as
`AGENT_RELAY_DEVIN_TOKEN`; it never appears in the build's parameters or
Terraform state, and the template should not set `AGENT_RELAY_DEVIN_TOKEN`
itself. The start step writes it to `remote-token` (mode `0600`) under the
module directory and the supervisor unsets the variable. The remote reads the
file into its own environment just before it starts, and the supervisor
deletes the file when the remote exits.

A start without the token, for example a person restarting the workspace,
removes any token left on disk, reports `idle`, and starts nothing.

## Download and verification

On a relay build the install step downloads the `devin-remote` the session
asked for:

1. The version is `agent_relay_devin_remote_binary_sha`, or, when that is
   empty, the short SHA in `<static_base_url>/latest_linux_<arch>`. `x86_64`
   maps to `x64` and `aarch64` to `arm64`.
2. It downloads `devin-remote_<sha>_linux_<arch>` and its `.sha256`, checks
   the binary against the published hash, and moves it into
   `$HOME/.devin/worker/cache` with the verified hash beside it.
3. A later start for the same version reuses the cached binary after
   re-checking it against that hash, and downloads nothing.

The install step never fails the build. A download that fails reports
`failed download`, a hash that does not match reports `failed checksum`, and
the binary never runs in either case.

To bake the binary into the image instead, point `remote_binary` at it. The
module then downloads nothing and runs that binary for every session,
whatever version the session asked for:

```tf
module "devin_remote" {
  source         = "registry.coder.com/coder/agent-relay-devin/coder"
  version        = "0.1.0"
  agent_id       = coder_agent.main.id
  install_remote = false
  remote_binary  = "/opt/devin/devin-remote"
}
```

The status scripts recognize the remote by the file name of `remote_binary`
in its command line, so point it at the binary itself, not at a wrapper that
execs a binary with another name, or a live remote reads as `orphaned`.

## Clean environment

`devin-remote serve` starts in `workdir` with a cleared environment. Only
these variables reach it, each only when the agent has it set: `PATH`,
`HOME`, `USER`, `LOGNAME`, `TMPDIR`, `LANG`, `TZ`, `DISPLAY`,
`WAYLAND_DISPLAY`, and `XAUTHORITY`. The module adds Devin's own:

- `DEVIN_OUTPOST_GATEWAY_URL` and `DEVIN_OUTPOST_SESSION_ID`, from the build.
- `DEVIN_OUTPOST_CONNECT_TOKEN`, the connect token.
- `DEVIN_REMOTE_STATE_DIR`, set to `<state_dir>/<session id>`.
- `DEVIN_CHROME_PATH` when `chrome_path` is set, and
  `DEVIN_OUTPOST_DESKTOP=true` when `desktop` is true.

Everything Devin runs inherits this environment. The connect token is in it
because Devin's spawn contract requires `DEVIN_OUTPOST_CONNECT_TOKEN`; the
module keeps it off every command line, but any process in the session can
read it. The agent's own variables, `CODER_AGENT_TOKEN` among them, are not
passed. Neither is anything other modules add with `coder_env`, for example
git identity or credential helper variables. Give Devin repository access
through files it can read instead, such as `~/.gitconfig` and a git
credential store written by a setup script.

## Persistence for suspend and resume

Devin suspends an idle session and resumes it later on a fresh claim. Agent
Relay stops the workspace on suspend and starts it again with
`agent_relay_devin_session_kind = "resume"`. For the session to resume with
its files, the volume that survives a workspace stop must cover `workdir`
(default `$HOME/devin`, where Devin keeps its repositories) and
`$HOME/.devin/worker` (the session state under `state_dir` and the binary
cache). A persistent home directory covers both.

Devin writes `.devin-outpost-stamps/<session id>` in `workdir` and
`outpost_stamp` in the session's state directory. On a resume, the start step
logs a warning naming each stamp that is missing, so a template whose storage
does not cover those paths can be told apart from a problem on Devin's side.
The remote still starts, and Devin warns the user.

## Template settings Agent Relay needs

- Allow users to cancel in-progress workspace jobs
  (`allow_user_cancel_workspace_jobs`), so Agent Relay can cancel a build in
  flight when it has to stop or delete the workspace.
- Do not set a dormancy threshold shorter than the pool's suspended
  retention, or a suspended session's workspace goes dormant before the
  session resumes.
- Do not enable autostart. A start without the relay has no connect token,
  so the workspace only idles.

## Session details the module does not use

`agent_relay_devin_image` and `agent_relay_devin_network_policy` carry the
image and the network policy Devin reports for the session. The module does
not act on them. The workspace sees them as `AGENT_RELAY_DEVIN_IMAGE` and
`AGENT_RELAY_DEVIN_NETWORK_POLICY` (JSON), so a template's own scripts can
choose tools or apply egress rules from them. `agent_relay_client_platform`
is exposed the same way as `AGENT_RELAY_CLIENT_PLATFORM`.

## Remote lifecycle

The start step launches `devin-remote serve` detached and exits, so the agent
reaches `ready` immediately. `devin-remote` exits `0` when its session
suspends or terminates; that is the end of the session, not a crash, and the
module does not restart it. A rejected token makes `devin-remote` retry
forever, so the supervisor gives it `connect_timeout` seconds (default 300)
to log `serving_log_pattern`, then stops it and reports
`failed connect-timeout`.

`agent_relay_status` reports one of:

| value                          | meaning                                                                  |
| ------------------------------ | ------------------------------------------------------------------------ |
| `pending`                      | start step running, supervisor has not written yet                       |
| `idle`                         | no connect token in this build: created by a person, or restarted by one |
| `working`                      | remote alive, not connected to Devin's gateway yet                       |
| `serving`                      | remote alive and connected (its log matches `serving_log_pattern`)       |
| `orphaned`                     | remote process gone without recording an exit                            |
| `done <code>`                  | remote exited with that status; `0` is the end of the session            |
| `failed download`              | the version or the binary could not be downloaded                        |
| `failed checksum`              | the binary does not match its published SHA-256; it never ran            |
| `failed unsupported-arch`      | no `devin-remote` build exists for the machine's architecture            |
| `failed remote-binary-missing` | `remote_binary` is not in the image, or the verified binary is gone      |
| `failed invalid-session`       | the session id is not a safe path component, or the gateway URL is empty |
| `failed connect-timeout`       | the remote did not connect within `connect_timeout` and was stopped      |

The connected line is coloured; the status script strips ANSI escape
sequences before it matches `serving_log_pattern` as a fixed string.
Renaming the `agent_relay_status` key breaks reaping.

`agent_relay_session_attached` reports `attached` while the state is
`working` and the remote is alive, and `stopped` otherwise. `devin-remote`
serves one session for its whole life, so a running remote is an attached
session.

Liveness means the pid the supervisor recorded is alive and its command line
still names the remote binary, so a reused pid reads as `orphaned`. The
generation, identity record, and cleanup handling match the
[Agent Relay Cursor](https://registry.coder.com/modules/coder/agent-relay-cursor)
module: each agent start stops the previous supervisor and remote before it
starts a new one, processes that ignore `SIGTERM` for 10 seconds get
`SIGKILL`, and a rebuild never leaves two remotes running when cleanup
succeeds. The stop script has a 20-second timeout; allow at least 30 seconds
for cleanup in the workspace shutdown budget.

## Scripts and logs

The module runs three steps through [coder-utils](https://registry.coder.com/modules/coder/coder-utils):
a pre-install cleanup that stops any remote a previous agent start left
running, an install step that downloads and verifies `devin-remote`, then a
start step that launches it. Everything lands under
`$HOME/.coder-modules/coder/agent-relay-devin`; the separate stop script uses
the same cleanup source and reports failures in its Coder script output:

| path                                     | contents                                                |
| ---------------------------------------- | ------------------------------------------------------- |
| `scripts/pre_install.sh`                 | the cleanup as it ran on start                          |
| `scripts/install.sh`, `scripts/start.sh` | the install and start steps as they ran                 |
| `scripts/supervise.sh`                   | the detached supervisor that owns the remote            |
| `install-result`                         | the install step's outcome, read by the start step      |
| `supervisors/`, `remotes/`               | one identity record per running supervisor and remote   |
| `started/`                               | one start claim per cleanup generation                  |
| `cleanup-complete`                       | fresh startup generation; removed on workspace stop     |
| `logs/*.log`                             | output of each step, plus the remote's own `remote.log` |
| `remote-state`                           | the supervisor's lifecycle line (`state_file`)          |
| `remote-token`                           | the connect token, removed when the remote exits        |
