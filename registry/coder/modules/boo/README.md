---
display_name: Boo
description: Run commands in persistent boo terminal sessions, one app per session.
icon: ../../../../.icons/coder.svg
verified: false
tags: [terminal, multiplexer, session, boo]
---

# Boo

![Boo sessions in a Coder workspace](../../.images/boo.png)

Install [boo](https://github.com/coder/boo) and run commands in persistent, named terminal sessions. Boo is a GNU screen-style terminal multiplexer built on [libghostty](https://github.com/ghostty-org/ghostty) (Zig). Pass a map of session names to commands and the module creates one `coder_app` per session. Clicking an app creates the session and attaches to it; clicking again reattaches to the running session.

```tf
module "boo" {
  source   = "registry.coder.com/coder/boo/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Usage

### Multiple sessions

Create separate persistent sessions for a dev server and an interactive shell, each with its own coder_app.

```tf
module "boo" {
  source   = "registry.coder.com/coder/boo/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  sessions = {
    server = "npm run dev"
    shell  = "bash"
  }
}
```

This creates:

- `coder_app` slugs `boo-server` and `boo-shell`
- Display names `Boo: server` and `Boo: shell`

### Multi-line commands

Session commands can be full shell scripts. The script is written to `~/.coder-modules/coder/boo/<session>/scripts/start.sh` and executed inside the boo session.

```tf
module "boo" {
  source   = "registry.coder.com/coder/boo/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  sessions = {
    watcher = <<-EOT
      #!/bin/bash
      while true; do
        echo "$(date): watching..."
        sleep 10
      done
    EOT
  }
}
```

Apps are named `Boo: watcher` with slug `boo-watcher`.

### Use pre/post install hooks

```tf
module "boo" {
  source              = "registry.coder.com/coder/boo/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.main.id
  pre_install_script  = "echo 'Preparing environment...'"
  post_install_script = "echo 'boo ready'"
  sessions            = { shell = "bash" }
}
```

### Serialize another module behind the boo install

Use `output.scripts` to wait for the boo install pipeline to complete before running downstream work.

```tf
module "boo" {
  source   = "registry.coder.com/coder/boo/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  sessions = { shell = "bash" }
}

resource "coder_script" "after_boo" {
  agent_id     = coder_agent.main.id
  display_name = "After Boo"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    coder exp sync want after-boo ${join(" ", module.boo.scripts)}
    coder exp sync start after-boo
    trap 'coder exp sync complete after-boo' EXIT
    echo "boo install complete"
  EOT
}
```

## Naming

App slugs and display names are derived from the `slug`, `display_name`, and session name variable.
For example:

| `slug`   | `display_name` | session name    | app slug            | display name         |
| -------- | -------------- | --------------- | ------------------- | -------------------- |
| `"boo"`  | `"Boo"`        | `"Claude Code"` | `"boo-claude-code"` | `"Boo: Claude Code"` |
| `"term"` | `"Terminal"`   | `"shell"`       | `"term-shell"`      | `"Terminal: shell"`  |

Session names are normalized for app slugs: lowercased, runs of non-alphanumeric characters replaced with a single hyphen, leading/trailing hyphens trimmed. Display names always use the raw session key.

## Troubleshooting

The install log is written under `~/.coder-modules/coder/boo/logs/`. Session scripts are written to `~/.coder-modules/coder/boo/<session>/scripts/start.sh`.

```
~/.coder-modules/coder/boo/
├── logs/
│   └── install.log
└── <session_name>/
    └── scripts/
        └── start.sh
```

Check `install.log` for installation errors. If an app does not connect, verify the session exists by running `boo ls` in a terminal.
