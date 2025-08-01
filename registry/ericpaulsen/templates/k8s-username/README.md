---
display_name: Kubernetes (Deployment) with Dynamic Username
description: Provision Kubernetes Deployments as Coder workspaces with your Username
icon: ../../../../.icons/kubernetes.svg
verified: true
tags: [kubernetes, container, username]
---

# Remote development on Kubernetes with dynamic usernames

Provision Kubernetes Pods as [Coder workspaces](https://coder.com/docs/workspaces) with this example template. This template
will run the workspace container as a non-root UID using your Coder username.

Here is the entrypoint logic in the template that enables Coder to source your username and write it to the Ubuntu operating system at start-up.

> These commands may differ if you run your workspace image with a distro other than Ubuntu.

```terraform
command = ["sh", "-c", <<EOF
    # Create user and setup home directory
    sudo useradd ${data.coder_workspace_owner.me.name} --home=/home/${data.coder_workspace_owner.me.name} --shell=/bin/bash --uid=1001 --user-group
    sudo chown -R ${data.coder_workspace_owner.me.name}:${data.coder_workspace_owner.me.name} /home/${data.coder_workspace_owner.me.name}
    
    # Switch to user and run agent
    exec sudo --preserve-env=CODER_AGENT_TOKEN -u ${data.coder_workspace_owner.me.name} sh -c '${coder_agent.main.init_script}'
EOF
]
```

<!-- TODO: Add screenshot -->

## Prerequisites

### Infrastructure

**Cluster**: This template requires an existing Kubernetes cluster

**Container Image**: This template uses the [codercom/enterprise-base:ubuntu image](https://github.com/coder/enterprise-images/tree/main/images/base) with some dev tools preinstalled. To add additional tools, extend this image or build it yourself.

### Authentication

This template authenticates using a `~/.kube/config`, if present on the server, or via built-in authentication if the Coder provisioner is running on Kubernetes with an authorized ServiceAccount. To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Architecture

This template provisions the following resources:

- Kubernetes Deployment (ephemeral)
- Kubernetes persistent volume claim (persistent on `/home/${username}`, where `${username}` is your Coder username)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the container image. Alternatively, individual developers can [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.
