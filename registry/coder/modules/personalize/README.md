---
display_name: Personalize
description: Allow developers to customize their workspace on start
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Personalize runs a developer-managed script when a Coder workspace starts. It lets each developer install personal tools or configure their environment without changing the shared Coder template.

The default configuration runs `~/personalize` on workspace start and writes its output to `~/personalize.log`.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "1.0.33"
  agent_id = coder_agent.main.id
}
```

## Create the personalize script

Create the script inside the workspace and make it executable. Keep startup commands idempotent because Coder runs the script on every workspace start.

```sh
cat > ~/personalize << 'EOF'
#!/usr/bin/env sh

command -v jq >/dev/null 2>&1 || echo "Install jq for this workspace"
EOF
chmod +x ~/personalize
```

If the script is missing or is not executable, Personalize prints instructions and exits without blocking the workspace with an error.

## Use custom paths

Set `path` when the script is stored elsewhere and `log_path` when its output should be written to a different location.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "1.0.33"
  agent_id = coder_agent.main.id

  path     = "/home/coder/scripts/personalize workspace.sh"
  log_path = "/home/coder/logs/personalize.log"
}
```

Coder creates a startup `coder_script` from this module. The script resolves the configured path, verifies that the developer's file exists and is executable, and then runs it as the workspace user. The module does not download software or require `sudo`; any network access or elevated privileges come from commands the developer places in their own script.
