---
display_name: Kubernetes (Air-gapped)
description: Provision Kubernetes Deployments as Coder workspaces with no outbound internet access
icon: ../../../../.icons/kubernetes.svg
verified: true
tags: [kubernetes, container, airgap, offline]
---

# Air-gapped Remote Development on Kubernetes Pods

Provision Kubernetes Pods as [Coder workspaces](https://coder.com/docs/workspaces) in clusters with no outbound internet access.

This template is the [Kubernetes (Deployment)](../kubernetes) template with every external download removed. Use it as a starting point for air-gapped proofs of concept and production deployments.

## What makes it air-gapped

Nothing in this template reaches the public internet when the template is pushed, when a workspace is built, or when a workspace starts:

| Step                  | Kubernetes (Deployment) template                         | This template                                         |
| --------------------- | -------------------------------------------------------- | ----------------------------------------------------- |
| Terraform providers   | Unpinned, downloaded from `registry.terraform.io`        | Pinned, served from your provider mirror              |
| Terraform modules     | `code-server` module from `registry.coder.com`           | None                                                  |
| Workspace image       | `codercom/example-base:ubuntu` from Docker Hub           | Required, from your internal registry                 |
| IDE                   | code-server downloaded from `code-server.dev` at startup | code-server baked into the image, started from `PATH` |
| Agent binary          | Downloaded from your Coder access URL                    | Downloaded from your Coder access URL (unchanged)     |
| Extension marketplace | `open-vsx.org`                                           | Disabled, or your internal mirror                     |

The only network paths a workspace needs are:

- Provisioner to the Kubernetes API and your Terraform provider mirror.
- Kubelet to your internal container registry.
- Workspace Pod to your Coder deployment's access URL.

## Prerequisites

### Infrastructure

**Cluster**: This template requires an existing Kubernetes cluster.

**Coder deployment**: Configure the Coder server for air-gapped use (external PostgreSQL, telemetry and update checks disabled, STUN disabled, and the template builder disabled or pointed at a mirror). See [Air-gapped deployments](https://coder.com/docs/install/prepare/airgap).

### Terraform providers

The provisioner must be able to install `coder/coder` and `hashicorp/kubernetes` without reaching `registry.terraform.io`. On a machine with internet access, download the providers this template needs into a mirror directory:

```shell
cd registry/coder/templates/kubernetes-airgapped
terraform providers mirror -platform=linux_amd64 ./providers
```

Copy `./providers` into your environment, then point Terraform at it on the Coder server or external provisioner. For a filesystem mirror:

```tf
# ~/.terraformrc, or the file referenced by TF_CLI_CONFIG_FILE
provider_installation {
  filesystem_mirror {
    path = "/home/coder/.terraform.d/plugins"
  }
}
```

You can serve the same directory as a [network mirror](https://developer.hashicorp.com/terraform/cli/config/config-file#network_mirror) instead. The [air-gapped deployment guide](https://coder.com/docs/install/prepare/airgap#air-gapped-container-images) shows how to bake the mirror into a custom Coder image.

### Workspace image

The `image` variable has no default. Set it to an image in your internal registry. The image must:

- Run as UID `1000` with a writable `/home/coder`.
- Include `curl` or `wget`, which the agent init script uses to download the agent from your Coder deployment.
- Include any IDEs and tools you want available. Nothing is installed at startup.

Build the image on a machine with internet access, then push it to your internal registry. For example, to add code-server to Coder's base image:

```dockerfile
FROM codercom/example-base:ubuntu

USER root
ARG CODE_SERVER_VERSION=4.141.1
RUN curl -fsSL https://code-server.dev/install.sh \
 | sh -s -- --method=standalone --prefix=/usr/local --version="${CODE_SERVER_VERSION}"
USER coder
```

```shell
docker build -t registry.example.internal/coder/workspace:ubuntu .
docker push registry.example.internal/coder/workspace:ubuntu
```

If the registry requires authentication, create a `kubernetes.io/dockerconfigjson` Secret in the workspace namespace and set `image_pull_secret` to its name.

If you don't want code-server, set `code_server_enabled = false`. Users can still connect with the web terminal, SSH, and port forwarding.

### Authentication

This template authenticates using a `~/.kube/config`, if present on the server, or via built-in authentication if the Coder provisioner is running on Kubernetes with an authorized ServiceAccount. To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Usage

```shell
coder templates push kubernetes-airgapped \
  --directory registry/coder/templates/kubernetes-airgapped \
  --variable namespace=coder-workspaces \
  --variable image=registry.example.internal/coder/workspace:ubuntu
```

## Verify there is no egress

To prove a workspace doesn't depend on the internet, apply a NetworkPolicy that only allows DNS and traffic to Coder, then create a workspace. This example assumes Coder runs in the `coder` namespace and workspaces run in `coder-workspaces`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: coder-workspaces-egress
  namespace: coder-workspaces
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: coder-workspace
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: coder
```

If the agent connects and code-server reports healthy, the workspace is running without internet access. If your access URL resolves to a load balancer outside the cluster, add an `ipBlock` rule for it.

## Add modules

This template uses no [modules](https://coder.com/docs/admin/templates/extending-templates/modules), so it never contacts `registry.coder.com`. To add modules from the [Coder Registry](https://registry.coder.com), make them available inside your network using one or more of these methods:

| Method                                                                    | Good fit for                                                   | Getting new module versions                         |
| ------------------------------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------- |
| [Vendor modules into the template](#vendor-modules-into-the-template)     | A few modules, no extra infrastructure                         | Copy the new version in and push the template again |
| [Mirror the registry](#mirror-the-registry-through-a-terraform-registry)  | Teams that already run JFrog Artifactory or a similar registry | Cached on first use; pre-warm before disconnecting  |
| [Host the Coder Registry internally](#host-the-coder-registry-internally) | Fully disconnected networks with an internal Git server        | Sync the repository from a connected machine        |

Whichever method you use, the module's scripts must not download anything when the workspace starts. Many modules install tools at runtime by default. Check each module's README for offline options, such as `offline = true` on [code-server](https://registry.coder.com/modules/coder/code-server), and bake the tools into the workspace image.

### Vendor modules into the template

Copy the module's source into the template directory and reference it with a local path. `coder templates push` uploads the whole directory, so the provisioner never fetches the module.

On a machine with internet access, check out the module's release tag and copy it into the template:

```shell
git clone --depth 1 --branch release/coder/code-server/v1.6.0 \
  https://github.com/coder/registry /tmp/coder-registry
mkdir -p registry/coder/templates/kubernetes-airgapped/modules
cp -r /tmp/coder-registry/registry/coder/modules/code-server \
  registry/coder/templates/kubernetes-airgapped/modules/code-server
```

Then reference the local copy. Local modules don't take a `version` argument:

```tf
module "code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "./modules/code-server"
  agent_id       = coder_agent.main.id
  offline        = true
  install_prefix = "/usr/local" # where the Dockerfile above installs code-server
}
```

If you replace the built-in code-server app with the module, set `code_server_enabled = false` so the workspace doesn't run two copies. To update a module, copy in the new release and push the template again.

### Mirror the registry through a Terraform registry

Terraform's `provider_installation` mirrors only cover providers, not modules. To mirror modules, proxy `registry.coder.com` through a Terraform registry inside your network, such as a JFrog Artifactory remote Terraform repository, and point module sources at it:

```tf
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "artifactory.example.internal/coder/code-server/coder"
  version  = "1.6.0"
  agent_id = coder_agent.main.id
  offline  = true
}
```

The provisioner's Terraform CLI configuration needs a `host` block and credentials for the mirror. Artifactory caches modules on first request, so if the mirror itself can't reach `registry.coder.com`, run `terraform init` against every module you need before disconnecting. Set `CODER_TEMPLATE_BUILDER_REGISTRY_URL` so the template builder generates sources that use the mirror. See [Mirror the Coder Registry with JFrog Artifactory](https://coder.com/docs/install/prepare/registry-mirror) for the full setup.

### Host the Coder Registry internally

The [coder/registry](https://github.com/coder/registry) repository contains the source of every module, and each module version is tagged `release/<namespace>/<module>/v<version>`. Copy the repository into your network and serve modules from it.

From a machine with internet access, mirror the repository to your internal Git server:

```shell
git clone --mirror https://github.com/coder/registry /tmp/coder-registry.git
cd /tmp/coder-registry.git
git push --mirror https://git.example.internal/coder/registry.git
```

Then use Git sources pinned to a release tag. Git sources take the version from `ref` rather than a `version` argument:

```tf
module "code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "git::https://git.example.internal/coder/registry.git//registry/coder/modules/code-server?ref=release/coder/code-server/v1.6.0"
  agent_id       = coder_agent.main.id
  offline        = true
  install_prefix = "/usr/local"
}
```

The Coder server or external provisioner needs `git` and credentials for your Git server. See [Private git repository](https://coder.com/docs/admin/templates/extending-templates/modules#private-git-repository). To pick up new module versions, run `git fetch --prune` in the mirror clone on a connected machine and push again.

If you'd rather serve modules from a Terraform registry than from Git, publish them from your clone to an Artifactory local Terraform repository. See [Artifactory Local Repository](https://coder.com/docs/admin/templates/extending-templates/modules#artifactory-local-repository).

## Client-side IDEs

The workspace needs no internet access, but some desktop IDEs download server components through the user's machine:

- **VS Code Desktop** (Remote - SSH) needs outbound access from the user's machine to Microsoft's update servers. See [Air-gapped deployments](https://coder.com/docs/install/prepare/airgap#microsoft-vs-code-remote---ssh).
- **JetBrains** IDEs can be configured for offline use. See [JetBrains air-gapped installation](https://coder.com/docs/admin/templates/extending-templates/jetbrains-airgapped).

## Architecture

This template provisions the following resources:

- Kubernetes Deployment (ephemeral)
- Kubernetes persistent volume claim (persistent on `/home/coder`)

When the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace, modify the container image.

> [!NOTE]
> This template is designed to be a starting point. Edit the Terraform to extend the template to support your use case. If you add modules, follow [Add modules](#add-modules) so the template stays air-gapped.
