---
display_name: Agent Substrate (Kubernetes)
description: Run each workspace in an Agent Substrate microVM that starts from a memory snapshot, behind a host name egress gateway
icon: ../../../../.icons/agent-substrate.svg
verified: false
tags: [kubernetes, microvm, sandbox, firewall, ai, prebuilds]
---

# Agent Substrate (Kubernetes)

Run each workspace as an [Agent Substrate](https://github.com/agent-substrate/substrate) actor: a Cloud Hypervisor microVM with its own kernel. Substrate starts every workspace from a memory snapshot of one workspace that has already booted, so a workspace starts in about 3 seconds even without a prebuild. Stop keeps the memory, so your files and running programs are still there after you start it again. You and your AI agents share the same sandbox and the same network rules.

> [!WARNING]
> This is an experiment. Agent Substrate is an early project (we tested v0.6.0), and this template needs a second Kubernetes cluster and a small service, coder-bridge, from this directory. Test it before you rely on it.

## How it works

```text
 Coder cluster                            Substrate cluster
 ┌──────────────────────────┐             ┌────────────────────────────────────┐
 │ Coder server             │◀── TCP ─────│ coder-bridge                       │
 │  provisioner writes:     │             │  TLS front for the agent           │
 │   ConfigMap ws-<id>      │── read ────▶│  controller: actors, egress policy │
 │   Secret ws-<id>-agent   │  (polling)  │  broker: GET /token                │
 └──────────────────────────┘             │        ▲                           │
                                          │        │ only through the gateway  │
                                          │  egress gateway                    │
                                          │        ▲                           │
                                          │  worker Pod: microVM               │
                                          │   coder-boot ─▶ coder agent        │
                                          └────────────────────────────────────┘
```

1. Terraform writes two objects to the `namespace` in the Coder cluster: a ConfigMap with the network profile, for the life of the workspace, and a Secret with the agent token, while the workspace is started.
2. coder-bridge reads them. It creates the actor and its egress policy, resumes the actor while the Secret exists, suspends it when the Secret is gone, and deletes it when the ConfigMap is gone.
3. In the actor, coder-boot asks coder-bridge for the agent token through the egress gateway, then starts `coder agent` as UID 1000. The gateway adds a signed token for the actor to each request, so a workspace can get only its own agent token.

When you claim a prebuild, Coder keeps its agent token. Terraform changes nothing, the actor keeps running, and the agent reconnects as yours. Terraform writes the two objects with the small `restapi` provider instead of `hashicorp/kubernetes`, because Terraform is most of the claim time.

## Startup speed

These are our measurements on one test host:

| Start                                      | Time to a connected agent |
| ------------------------------------------ | ------------------------- |
| From a preset, with a prebuild             | About 1.2 s               |
| Custom profile, or no prebuild             | About 3 s                 |
| Start after stop, memory and programs kept | About 3 s                 |

## Prerequisites

- **A Substrate cluster:** Agent Substrate v0.6.0 needs Kubernetes 1.37 or the beta `PodCertificateRequest` and `ClusterTrustBundle` APIs, and nodes with nested virtualization. We used a kind cluster on one EC2 host.
- **A Coder cluster:** the provisioner must run in it, because the template calls the Kubernetes API with the provisioner's ServiceAccount token. The defaults of `kube_api_url`, `kube_token_path`, and `kube_ca_path` are the in-cluster values.
- **coder-bridge** in the Substrate cluster, and the manifests in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-substrate/cluster). The steps are in [`cluster/README.md`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-substrate/cluster/README.md).
- **A workspace image** built from [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-substrate/build/Dockerfile). It needs a base image with the Coder agent at `/usr/local/bin/coder`, at a version that matches your Coder server, and a `coder` user with UID 1000. The [Plain Sandbox (Kubernetes)](https://registry.coder.com/templates/coder-labs/kubernetes-sandboxed) image works.
- **Coder Premium** for prebuilds. Without it, set `prebuild_instances` to `0`.

## Variables

| Variable             | Default                                                | Description                                                                  |
| -------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `namespace`          | `coder-substrate`                                      | Namespace in the Coder cluster that coder-bridge reads.                      |
| `prebuild_instances` | `1`                                                    | Prebuilt workspaces for each preset. Each one keeps a Substrate worker busy. |
| `kube_api_url`       | `https://kubernetes.default.svc`                       | Kubernetes API of the Coder cluster.                                         |
| `kube_token_path`    | `/var/run/secrets/kubernetes.io/serviceaccount/token`  | File with the provisioner's token for that API.                              |
| `kube_ca_path`       | `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` | File with the CA certificate of that API.                                    |

The actor size (2 CPUs and 4 GiB) and the image are set in [`cluster/actor-template.yaml`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-substrate/cluster/actor-template.yaml), not in the template.

## Network isolation

Users pick a profile in the **Network isolation** dropdown when they create a workspace. They cannot change it later. Each profile except Custom is a preset with `prebuild_instances` prebuilds.

| Profile                       | Hosts it can reach, in addition to Coder                              |
| ----------------------------- | --------------------------------------------------------------------- |
| Fully isolated (default)      | None                                                                  |
| GitHub only                   | `github.com`, `api.github.com`, and the GitHub download hosts         |
| GitHub and package registries | GitHub, npm, the Go module proxy, and PyPI                            |
| Custom                        | The host names and ports (443, 80, or both) that you type in the form |

The egress gateway is outside the microVM, so nothing in the workspace can turn it off. It allows HTTPS on port 443 without decrypting it, and HTTP on port 80 if the profile has it. It blocks IP addresses, UDP, ICMP, SSH, DNS for other names, cloud metadata, and the cluster. There is no Public internet profile, because Substrate rules must name each host.

With Custom, `*.example.com` allows `www.example.com`, not `example.com`. The form rejects IP addresses, names without a dot, `*.com`, and names that end in `.local`, `.internal`, `.svc`, or `cluster.local`. The build checks the same rules again. The host lists for the other profiles are in `local.profiles` in `main.tf`.

## Limits

- **Not production:** Substrate is early, and we ran it on kind on one host.
- **One worker per running workspace:** prebuilds included. A workspace that starts when every worker is busy waits until one is free, and Coder shows the agent as connecting. A stopped workspace needs only snapshot storage.
- **Allowed hosts can still receive data:** the gateway sees only the host name. An agent can push to any GitHub repository its credentials allow.
- **HTTPS and HTTP only:** SSH to Git hosts does not work. Use Git over HTTPS.
- **No IDE apps:** the template has the agent, terminals, and SSH. It does not add code-server.
- **`AWS_LAMBDA_*` variables** are set in the workspace. An actor has only a link-local address, and Tailscale, which the Coder agent uses, treats such a host as offline unless it runs in AWS Lambda.
- **One image and size for every workspace:** they come from the actor template. To change them, delete every workspace from this template first, because an actor template cannot change while actors use it.
