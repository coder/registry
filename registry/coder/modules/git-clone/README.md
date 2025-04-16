---
display_name: Git Clone
description: Clone a Git repository by URL and skip if it exists.
icon: ../../../../.icons/git.svg
maintainer_github: coder
verified: true
tags: [git, helper]
---

# Git Clone

This module allows you to automatically clone a repository by URL and skip if it exists in the base directory provided.

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://github.com/coder/coder"
}
```

## Examples

### Custom Path

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://github.com/coder/coder"
  base_dir = "~/projects/coder"
}
```

### Git Authentication

To use with [Git Authentication](https://coder.com/docs/v2/latest/admin/git-providers), add the provider by ID to your template:

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://github.com/coder/coder"
}

data "coder_git_auth" "github" {
  id = "github"
}
```

## GitHub clone with branch name

To GitHub clone with a specific branch like `feat/example`

```tf
# Prompt the user for the git repo URL
data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository"
  default      = "https://github.com/coder/coder/tree/feat/example"
}

# Clone the repository for branch `feat/example`
module "git_clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = data.coder_parameter.git_repo.value
}

# Create a code-server instance for the cloned repository
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  order    = 1
  folder   = "/home/${local.username}/${module.git_clone[count.index].folder_name}"
}

# Create a Coder app for the website
resource "coder_app" "website" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.example.id
  order        = 2
  slug         = "website"
  external     = true
  display_name = module.git_clone[count.index].folder_name
  url          = module.git_clone[count.index].web_url
  icon         = module.git_clone[count.index].git_provider != "" ? "/icon/${module.git_clone[count.index].git_provider}.svg" : "/icon/git.svg"
}
```

Configuring `git-clone` for a self-hosted GitHub Enterprise Server running at `github.example.com`

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://github.example.com/coder/coder/tree/feat/example"
  git_providers = {
    "https://github.example.com/" = {
      provider = "github"
    }
  }
}
```

## GitLab clone with branch name

To GitLab clone with a specific branch like `feat/example`

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://gitlab.com/coder/coder/-/tree/feat/example"
}
```

Configuring `git-clone` for a self-hosted GitLab running at `gitlab.example.com`

```tf
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.example.id
  url      = "https://gitlab.example.com/coder/coder/-/tree/feat/example"
  git_providers = {
    "https://gitlab.example.com/" = {
      provider = "gitlab"
    }
  }
}
```

## Git clone with branch_name set

Alternatively, you can set the `branch_name` attribute to clone a specific branch.

For example, to clone the `feat/example` branch:

```tf
module "git-clone" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/modules/git-clone/coder"
  version     = "1.0.18"
  agent_id    = coder_agent.example.id
  url         = "https://github.com/coder/coder"
  branch_name = "feat/example"
}
```

## Git clone with different destination folder

By default, the repository will be cloned into a folder matching the repository name. You can use the `folder_name` attribute to change the name of the destination folder to something else.

For example, this will clone into the `~/projects/coder/coder-dev` folder:

```tf
module "git-clone" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/modules/git-clone/coder"
  version     = "1.0.18"
  agent_id    = coder_agent.example.id
  url         = "https://github.com/coder/coder"
  folder_name = "coder-dev"
  base_dir    = "~/projects/coder"
}
```
