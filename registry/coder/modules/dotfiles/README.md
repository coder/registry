---
display_name: Dotfiles
description: Allow developers to optionally bring their own dotfiles repository to customize their shell and IDE settings!
icon: ../../../../.icons/dotfiles.svg
verified: true
tags: [helper, dotfiles]
---

# Dotfiles

Allow developers to optionally bring their own [dotfiles repository](https://dotfiles.github.io).

This will prompt the user for their dotfiles repository URL on template creation using a `coder_parameter`.

Under the hood, this module uses the [coder dotfiles](https://coder.com/docs/v2/latest/dotfiles) command.

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Apply dotfiles as the current user

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
}
```

### Apply dotfiles as another user (only works if sudo is passwordless)

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
  user     = "root"
}
```

### Apply the same dotfiles as the current user and root (the root dotfiles can only be applied if sudo is passwordless)

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.3.0"
  agent_id = coder_agent.example.id
}

module "dotfiles-root" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/dotfiles/coder"
  version      = "1.3.0"
  agent_id     = coder_agent.example.id
  user         = "root"
  dotfiles_uri = module.dotfiles.dotfiles_uri
}
```

## SSH vs HTTPS URLs

If your Git provider (e.g. GitLab, GitHub Enterprise) restricts HTTPS cloning, use an SSH URL instead:

```text
# HTTPS (may fail if HTTP cloning is disabled)
https://gitlab.example.com/user/dotfiles.git

# SSH (uses the workspace's SSH key)
git@gitlab.example.com:user/dotfiles.git
```

During workspace startup the dotfiles clone happens early, before external auth tokens may be fully available. SSH URLs avoid this issue because they authenticate via the workspace's SSH key rather than a token.

## Setting a default dotfiles repository

You can set a default dotfiles repository for all users by setting the `default_dotfiles_uri` variable:

```tf
module "dotfiles" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/dotfiles/coder"
  version              = "1.3.0"
  agent_id             = coder_agent.example.id
  default_dotfiles_uri = "https://github.com/coder/dotfiles"
}
```
