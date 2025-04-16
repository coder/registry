---
display_name: Git Config
description: Stores Git configuration from Coder credentials
icon: ../../../../.icons/git.svg
maintainer_github: coder
verified: true
tags: [helper, git]
---

# git-config

Runs a script that updates git credentials in the workspace to match the user's Coder credentials, optionally allowing to the developer to override the defaults.

```tf
module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-config/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}
```

TODO: Add screenshot

## Examples

### Allow users to override both username and email

```tf
module "git-config" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/modules/git-config/coder"
  version            = "1.0.15"
  agent_id           = coder_agent.example.id
  allow_email_change = true
}
```

TODO: Add screenshot

## Disallowing users from overriding both username and email

```tf
module "git-config" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/modules/git-config/coder"
  version               = "1.0.15"
  agent_id              = coder_agent.example.id
  allow_username_change = false
  allow_email_change    = false
}
```
