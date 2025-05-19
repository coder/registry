---
display_name: Git commit signing
description: Configures Git to sign commits using your Coder SSH key
icon: ../../../../.icons/git.svg
maintainer_github: coder
verified: true
tags: [helper, git]
---

# git-commit-signing

> [!IMPORTANT]
> This module will only work with Git versions >=2.34, prior versions [do not support signing commits via SSH keys](https://lore.kernel.org/git/xmqq8rxpgwki.fsf@gitster.g/).

This module downloads your SSH key from Coder and uses it to sign commits with Git.
It requires `curl` and `jq` to be installed inside your workspace.

Please observe that using the SSH key that's part of your Coder account for commit signing, means that in the event of a breach of your Coder account, or a malicious admin, someone could perform commit signing pretending to be you.

This module has a chance of conflicting with the user's dotfiles / the personalize module if one of those has configuration directives that overwrite this module's / each other's git configuration.

```tf
module "git-commit-signing" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-commit-signing/coder"
  version  = "1.0.11"
  agent_id = coder_agent.example.id
}
```
