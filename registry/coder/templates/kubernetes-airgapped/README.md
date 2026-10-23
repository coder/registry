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
> This template is designed to be a starting point. Edit the Terraform to extend the template to support your use case. If you add [modules](https://coder.com/docs/admin/templates/extending-templates/modules), serve them from an [internal registry mirror](https://coder.com/docs/install/prepare/registry-mirror) so the template stays air-gapped.
