---
display_name: Dotfiles
description: Allow developers to optionally bring their own dotfiles repository to customize their shell and IDE settings!
icon: ../../../../.icons/dotfiles.svg
maintainer_github: coder
verified: true
tags: [helper]
---

# Dotfiles

Allow developers to optionally bring their own [dotfiles repository](https://dotfiles.github.io).

This will prompt the user for their dotfiles repository URL on template creation using a `coder_parameter`.

Under the hood, this module uses the [coder dotfiles](https://coder.com/docs/v2/latest/dotfiles) command.

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.0.29"
  agent_id = coder_agent.example.id
}
```

## Examples

### Apply dotfiles as the current user

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.0.29"
  agent_id = coder_agent.example.id
}
```

### Apply dotfiles as another user (only works if sudo is passwordless)

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.0.29"
  agent_id = coder_agent.example.id
  user     = "root"
}
```

### Apply the same dotfiles as the current user and root (the root dotfiles can only be applied if sudo is passwordless)

```tf
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.0.29"
  agent_id = coder_agent.example.id
}

module "dotfiles-root" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/dotfiles/coder"
  version      = "1.0.29"
  agent_id     = coder_agent.example.id
  user         = "root"
  dotfiles_uri = module.dotfiles.dotfiles_uri
}
```

## Setting a default dotfiles repository

You can set a default dotfiles repository for all users by setting the `default_dotfiles_uri` variable:

```tf
module "dotfiles" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/dotfiles/coder"
  version              = "1.0.29"
  agent_id             = coder_agent.example.id
  default_dotfiles_uri = "https://github.com/coder/dotfiles"
}
```
