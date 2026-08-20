---
display_name: mise install
description: Install mise and run `mise install` inside a cloned repository.
icon: ../../../../.icons/code.svg
verified: false
tags: [helper, mise, devtools]
---

# mise install

Installs [`mise`](https://mise.jdx.dev/getting-started.html) on the workspace and runs `mise install` inside a repository directory so language runtimes and tools declared in `.mise.toml` / `.tool-versions` are provisioned before the user starts working.

Designed to compose with the [`coder/git-clone`](https://registry.coder.com/modules/coder/git-clone) module: pass `module.git_clone.repo_dir` as `repo_dir`.

```tf
module "mise_install" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/mise-install/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  repo_dir = module.git_clone[count.index].repo_dir
}
```

The install script downloads `mise` from `https://mise.run` into `install_dir` (defaults to `$HOME/.local/bin`) and appends `mise activate` to `~/.bashrc` and `~/.zshrc`. The post-install script then runs `mise trust` (optional) and `mise install` inside `repo_dir`.

## Examples

### Compose with `coder/git-clone`

```tf
module "git_clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.3"
  agent_id = coder_agent.main.id
  url      = "https://github.com/example/repo"
}

module "mise_install" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/droopy4096/mise-install/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  repo_dir = module.git_clone[count.index].repo_dir
}
```

### Disable shell activation and `mise trust`

Use this when the workspace image already activates `mise` globally, or the repository does not use `.mise.toml`:

```tf
module "mise_install" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/droopy4096/mise-install/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  repo_dir        = module.git_clone[count.index].repo_dir
  activate_shells = []
  mise_trust      = false
}
```

### Custom install directory

```tf
module "mise_install" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/droopy4096/mise-install/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.main.id
  repo_dir    = module.git_clone[count.index].repo_dir
  install_dir = "$HOME/.mise/bin"
}
```

## Execution order

This module uses [`coder/coder-utils`](https://registry.coder.com/modules/coder/coder-utils) to run two ordered scripts via `coder exp sync`:

1. **Install Script** — installs `mise` and (optionally) configures shell activation.
2. **Post-Install Script** — waits for the clone to complete, then runs `mise trust` and `mise install` in `repo_dir`.

Coder starts every `coder_script` on an agent in parallel, so this module's post-install script cannot use `coder exp sync` to wait on `git-clone` (git-clone does not participate in `coder exp sync`). Instead, the post-install script polls for `${repo_dir}/.git` and only runs `mise install` once the clone has finished. The bound is controlled by `wait_seconds` (default `300`). If the timeout expires, the script logs a message and exits `0` without running `mise install`.

### Custom wait timeout

```tf
module "mise_install" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/droopy4096/mise-install/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  repo_dir     = module.git_clone[count.index].repo_dir
  wait_seconds = 900 # wait up to 15 minutes for large clones
}
```

## Troubleshooting

Scripts and logs are written under a per-module root:

- Scripts: `$HOME/.coder-modules/droopy4096/mise-install/scripts/{install.sh,post_install.sh}`
- Logs: `$HOME/.coder-modules/droopy4096/mise-install/logs/{install.log,post_install.log}`

If `mise install` fails, inspect `post_install.log` for the exact `mise` output. Common causes:

- Missing `.mise.toml` / `.tool-versions` in `repo_dir`.
- Untrusted config (rerun with `mise_trust = true`).
- Network egress restrictions on downloading plugins from `mise.jdx.dev`.
