---
display_name: Github Upload Public Key
description: Automates uploading Coder public key to Github so users don't have to.
icon: ../../../../.icons/github.svg
verified: true
tags: [helper, git]
---

# github-upload-public-key

Templates that utilize Github External Auth can automatically ensure that the Coder public key is uploaded to Github so that users can clone repositories without needing to upload the public key themselves.

```tf
module "github-upload-public-key" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/github-upload-public-key/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}
```

## Requirements

This module requires `curl` and `jq` to be installed inside your workspace.

Github External Auth must be enabled in the workspace for this module to work. The Github app that is configured for external auth must have both read and write permissions to "Git SSH keys" in order to upload the public key. Additionally, a Coder admin must also have the `admin:public_key` scope added to the external auth configuration of the Coder deployment. For example:

```txt
CODER_EXTERNAL_AUTH_0_ID="USER_DEFINED_ID"
CODER_EXTERNAL_AUTH_0_TYPE=github
CODER_EXTERNAL_AUTH_0_CLIENT_ID=xxxxxx
CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=xxxxxxx
CODER_EXTERNAL_AUTH_0_SCOPES="repo,workflow,admin:public_key"
```

Note that the default scopes if not provided are `repo,workflow`. If the module is failing to complete after updating the external auth configuration, instruct users of the module to "Unlink" and "Link" their Github account in the External Auth user settings page to get the new scopes.

## Example

Using a coder github external auth with a non-default id: (default is `github`)

```tf
data "coder_external_auth" "github" {
  id = "myauthid"
}

module "github-upload-public-key" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/coder/github-upload-public-key/coder"
  version          = "1.0.31"
  agent_id         = coder_agent.example.id
  external_auth_id = data.coder_external_auth.github.id
}
```
