---
display_name: Kubernetes (agent-sandbox)
description: Run each workspace in an agent-sandbox Sandbox with gVisor or Kata isolation and a NetworkPolicy firewall
icon: ../../../../.icons/agent-sandbox.svg
verified: false
tags: [kubernetes, agent-sandbox, sandbox, gvisor, kata, ai]
---

# Kubernetes agent-sandbox

Run each workspace in a Sandbox from [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox), a Kubernetes SIG project. You and your AI agent work in the same sandbox, with one Coder agent named `dev`. The sandbox runs under gVisor or a Kata microVM, so it does not share the node kernel. A Kubernetes NetworkPolicy works as the firewall, and ClusterNetworkPolicy or Cilium can add more advanced rules (see [Firewall](#firewall)). By default the workspace can reach only the Coder server. Code in the workspace can still use that connection, for example with the Coder session token that the AI Gateway needs (see [Limits](#limits)).

Claude Code reaches Anthropic through the Coder AI Gateway, so it works with no internet access.

## Why agent-sandbox

agent-sandbox adds Kubernetes primitives for running agentic workloads:

- **Kernel isolation at the cluster level.** A SandboxTemplate sets the runtime (gVisor, Kata with QEMU, or Kata with Cloud Hypervisor), the image, the security settings, and the network rules. A scratch workspace can only claim a sandbox from these templates, and the Coder provisioner never creates Pods.
- **Cluster-level warm pools.** A SandboxWarmPool keeps booted sandboxes ready for any client of the cluster, not only Coder, and it does not need Coder Premium.
- **A growing ecosystem.** SDKs, a router, and a managed version on GKE. The API already has a suspended mode and expiry, and GKE adds Pod snapshots. This template does not use them yet.
- **Firewall.** agent-sandbox uses plain Kubernetes NetworkPolicy, with a secure default for templates that set no rules. This template sets its own rules for each network profile, and adds an optional cluster-wide guardrail.

## Startup speed

Workspace speed and Pod startup speed are not the same. Pod startup is the time until the sandbox runs, and agent-sandbox makes it very short: a scratch home claims a booted sandbox from a warm pool in 50 to 80 ms. Workspace speed is the time from create until you can connect, and it also includes the Coder build: the provisioner job, Terraform, and the agent connecting to the Coder server. Most of a fast start is the Coder build, so a warm pool and a prebuild are about as fast.

In our Amazon EKS test cluster (`m7i.2xlarge` nodes, VPC CNI), from create to a connected agent:

| Workspace                                              | Ready in     |
| ------------------------------------------------------ | ------------ |
| Scratch home, from a warm pool                         | 3.5 to 6.5 s |
| Persistent home, from a prebuild                       | 4 to 7 s     |
| Persistent home, no prebuild, gVisor                   | about 17 s   |
| Persistent home, no prebuild, Kata QEMU                | about 19 s   |
| Persistent home, no prebuild, with a coder/coder clone | about 58 s   |

![Creating agent-sandbox workspaces on Amazon EKS, in real time](../../.images/kubernetes-agent-sandbox.gif)

These all add to the speed:

1. **The image.** [`build/Dockerfile`](build/Dockerfile) adds the Coder agent, code-server, and Claude Code to `codercom/enterprise-base:ubuntu`. The Pod runs the agent from the image instead of the init script that downloads it, and the code-server module runs with `offline = true`. So a start downloads nothing, and it also works in Fully isolated, which has no internet. The image is about 800 MB compressed, so pull it ahead of time with a DaemonSet, or the first Pod on a node waits for the pull.
2. **Prebuilds** (Premium). Each persistent preset keeps `prebuild_instances` running workspaces, and the GitHub only and Public internet ones have already cloned `git_repo_url`. A claim reuses the Sandbox and its disk, so the Pod does not restart.
3. **Warm pools.** Scratch homes claim a booted sandbox from agent-sandbox in 50 to 80 ms. GitHub only pools clone `git_repo_url` before a claim.
4. **The runtime.** On a cold start, gVisor added about 0.2 s over a normal container, Kata Cloud Hypervisor about 1.5 s, and Kata QEMU about 2.6 s. Prebuilds and warm pools hide this.
5. **Terraform.** Coder caches modules, but downloads providers on every build unless the provisioner has a provider cache or mirror. coder/coder PRs [#29825](https://github.com/coder/coder/pull/29825) and [#29827](https://github.com/coder/coder/pull/29827), still open, skip `terraform init` and save about 3.3 s.
6. **The Coder server.** The Helm chart's default CPU limit of 2 throttled builds. With 4 CPUs, each start was about 2.4 s faster.
7. **The disk.** A StorageClass with `volumeBindingMode: WaitForFirstConsumer` creates the disk in the node's zone. Moving an EBS volume to another node adds 5 to 10 s.

## Is agent-sandbox a good fit?

Coder already handles most of the workspace lifecycle. It creates and deletes the Pods, starts and stops workspaces on a schedule, stops idle ones, keeps prebuilds ready, and runs the agent and the apps. agent-sandbox adds its own lifecycle under that: Sandboxes, claims, warm pools, and expiry. That is one more controller to run and upgrade.

If only Coder uses the cluster, you have Coder Premium, and you trust template authors to set the runtime, the [Kubernetes template](../../../coder/templates/kubernetes) with a `runtimeClassName` and a NetworkPolicy gives the same isolation with fewer parts. Speed alone is not a reason to use agent-sandbox, because prebuilds are about as fast as warm pools.

agent-sandbox is a good fit when:

- Cluster administrators, not template authors, must own the runtime, the image, and the network rules.
- Other clients, such as SDKs, CI jobs, or agent platforms, use the same sandboxes and warm pools.
- You want fast starts without Coder Premium.
- You plan to use the suspended mode, expiry, or Pod snapshots on GKE.

## agent-sandbox vs Pods

|                   | Plain Pods                         | Pods + Coder                         | agent-sandbox + Coder (this template)                                                 |
| ----------------- | ---------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------- |
| Kernel isolation  | Set `runtimeClassName` on each Pod | The template sets the runtime        | The cluster administrator sets the runtime once in a SandboxTemplate                  |
| Firewall          | NetworkPolicies that you write     | The template creates a NetworkPolicy | The template, or a shared policy for each SandboxTemplate, plus an optional guardrail |
| Fast start        | No, every Pod starts cold          | Prebuilds (Premium)                  | Prebuilds, and warm pools that need no Premium                                        |
| Warm pools        | No                                 | No, prebuilds serve Coder only       | SandboxWarmPools, for Coder and any other client in the cluster                       |
| Who creates Pods  | You                                | The Coder provisioner                | For scratch homes, agent-sandbox. The provisioner only claims from admin-owned pools  |
| Lifecycle         | Kubernetes only                    | Start, stop, and TTL in Coder        | Coder, plus the Sandbox API: expiry, a suspended mode, and Pod snapshots on GKE       |
| IDE and AI agents | No                                 | Coder agent, apps, AI Gateway        | Coder agent, apps, AI Gateway                                                         |
| Extra components  | None                               | None                                 | The agent-sandbox controller                                                          |

## Prerequisites

Required:

- **A Kubernetes cluster** with a network plugin that enforces NetworkPolicy, and a StorageClass for the home disk.
- **agent-sandbox** v1.0.4 or later, with the extensions.
- **gVisor** `release-20261019.0` or later on the nodes, with a `gvisor` RuntimeClass. Older releases block on an empty write to a terminal, so the web terminal takes no input.
- **The cluster setup** in [`cluster/`](cluster): a Terraform configuration that creates the namespace, RBAC, and warm pools, and prints the template variables. See [`cluster/README.md`](cluster/README.md).
- **The image**, built from [`build/Dockerfile`](build/Dockerfile).
- **Access to the cluster** for the Coder provisioner. The template uses the in-cluster ServiceAccount, or `~/.kube/config` with `use_kubeconfig = true`.

Optional:

- **Kata nodes**, for the Kata runtimes: a node group with `/dev/kvm`, such as EC2 instances with nested virtualization. See [Install the runtimes](cluster/README.md#2-install-the-runtimes).
- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.
- **Warm pools**, for scratch homes. `cluster/` creates them by default. Set `scratch_profiles` to empty in both to skip them.
- **A DaemonSet that pulls the image** on every node.
- **A provider cache or mirror** for the Coder provisioner.
- **The guardrail**, on Amazon EKS with VPC CNI v1.21.1 or later.

## Quick start

1. Build the image and push it to your registry. See [Build the image](#build-the-image).
2. Set up the cluster with the Terraform configuration in [`cluster/`](cluster). See [`cluster/README.md`](cluster/README.md).
3. Push the template with the variables that `cluster/` prints:

   ```sh
   cd cluster
   terraform output -raw coder_variables > ~/kubernetes-agent-sandbox.yaml
   cd ..
   coder templates push kubernetes-agent-sandbox -d . --variables-file ~/kubernetes-agent-sandbox.yaml
   ```

## Build the image

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_VERSION=2.30.0 \
  -t registry.example.com/coder/workspace:v2.30.0 --push build
```

- Match `CODER_VERSION` to your Coder server, and rebuild when you upgrade Coder. `CODER_BINARY_URL`, such as `https://coder.example.com/bin/coder-linux-amd64`, copies the binary from your server instead of GitHub.
- `INSTALL_CODE_SERVER=false` and `INSTALL_CLAUDE_CODE=false` leave out the tools.
- Use a fixed tag or a digest. The template rejects `:latest`, because `imagePullPolicy: IfNotPresent` would keep an old copy on the nodes.

## Parameters

| Parameter                               | Options                                                                                                             | Notes                                                                                                                                                                        |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network isolation (`network_isolation`) | Fully isolated (default), GitHub only, Public internet                                                              | See [Network egress](#network-egress). You cannot change it after create.                                                                                                    |
| Kernel isolation (`runtime`)            | The runtimes in `runtimes`: gVisor, Kata microVM (QEMU), Kata microVM (Cloud Hypervisor). The first is the default. | The RuntimeClass of a persistent home, or the warm pool `coder-<runtime>` (Fully isolated) or `coder-<runtime>-github` (GitHub only) of a scratch home.                      |
| Home directory (`home`)                 | Persistent (default), Scratch                                                                                       | Persistent: a disk at `/home/coder`, kept on stop. Scratch: a booted sandbox from the warm pool, deleted on stop. Scratch is offered for the profiles in `scratch_profiles`. |

Presets:

| Preset                       | Prebuilds                          |
| ---------------------------- | ---------------------------------- |
| Fully isolated (default)     | `prebuild_instances`               |
| GitHub only                  | `prebuild_instances`               |
| Public internet              | `prebuild_instances`               |
| Fully isolated, scratch home | None. The warm pool keeps it fast. |
| GitHub only, scratch home    | None. The warm pool keeps it fast. |

## Variables

The Scratch column shows which variables also apply to a scratch home. For a scratch home, the image, the Coder address, and the network rules come from the warm pools that [`cluster/`](cluster) creates. Push the template with the `coder_variables` output of `cluster/`, so the two agree. See [Push the template with the same values](cluster/README.md#5-push-the-template-with-the-same-values).

| Variable              | Default           | Scratch | Description                                                                                                                                                                                                                                                                                           |
| --------------------- | ----------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `namespace`           | none              | Yes     | The namespace for workspaces, with the Role from `cluster/`.                                                                                                                                                                                                                                          |
| `workspace_image`     | none              | No      | The image built from `build/Dockerfile`, with a tag other than `:latest`, or a digest.                                                                                                                                                                                                                |
| `coder_egress_cidrs`  | none              | No      | The IPv4 CIDR ranges of the Coder server as workspaces see it, such as the IP of its load balancer, for example `["203.0.113.10/32"]`. Every profile allows them.                                                                                                                                     |
| `coder_egress_port`   | from the URL      | No      | The TCP port to the Coder server. Empty uses the port of the access URL, or 443 for https and 80 for http.                                                                                                                                                                                            |
| `coder_host_ip`       | `""`              | No      | The IPv4 address of the access URL host. Fully isolated blocks DNS, so if the access URL uses a host name, the template adds this address to `/etc/hosts`. A persistent build with Fully isolated fails if the access URL uses a host name and this is empty. `cluster/` does the same for the pools. |
| `runtimes`            | `gvisor`          | Yes     | The runtimes users can pick, comma-separated, in order: `gvisor`, `kata-qemu`, `kata-clh`. The first is the default and is used by the presets. Offer only RuntimeClasses that the cluster has.                                                                                                       |
| `scratch_profiles`    | `isolated,github` | Yes     | The network profiles that offer a scratch home, comma-separated. Each needs warm pools from `cluster/` for every runtime. Empty turns off scratch homes.                                                                                                                                              |
| `home_disk_size`      | `10`              | No      | The size of the persistent home disk, in GiB.                                                                                                                                                                                                                                                         |
| `storage_class_name`  | `""`              | No      | The StorageClass of the home disk. Empty uses the cluster default.                                                                                                                                                                                                                                    |
| `prebuild_instances`  | `1`               | No      | Prebuilt workspaces per persistent preset (Premium). `0` turns them off.                                                                                                                                                                                                                              |
| `git_repo_url`        | `""`              | No      | A Git repository to clone into `/home/coder`, for example `https://github.com/coder/coder`. Only GitHub only and Public internet workspaces clone it. A prebuild clones it before a claim, so a claim does not wait.                                                                                  |
| `enable_ai_gateway`   | `true`            | Yes     | Send Claude Code requests through the Coder AI Gateway (Premium).                                                                                                                                                                                                                                     |
| `network_policy_gate` | `true`            | No      | Start the agent only after a connection to the Kubernetes API server fails, and stop it if one succeeds later. Turn it off only if a profile can reach the API server (see [Network egress](#network-egress)).                                                                                        |
| `use_kubeconfig`      | `false`           | Yes     | Use `~/.kube/config` on the Coder host instead of the in-cluster ServiceAccount.                                                                                                                                                                                                                      |

## How it works

- **Persistent home:** Terraform creates a disk, a NetworkPolicy for the profile, a Secret with the agent token, and a Sandbox. Stop deletes everything except the disk.
- **Scratch home:** Terraform creates only a SandboxClaim. agent-sandbox hands it a booted Pod from the warm pool, and the Pod reads the agent token from an annotation. Stop deletes the Pod and its home.
- **Policy check:** before the agent starts, the Pod waits until the Kubernetes API server is unreachable, which shows that its NetworkPolicy is in force. It checks again every 5 s and stops the agent if the API server becomes reachable. VPC CNI can apply a new Pod's policy up to 30 s late, and can drop it while the Pod runs.
- **Pods:** run as user 1000 with no capabilities and no ServiceAccount token, use `8.8.8.8` and `1.1.1.1` for DNS, and request 500m CPU and 1 GiB (`shared/defaults.json`).
- **Apps:** code-server, and Claude Code, which continues the last conversation in `/home/coder`.

## Firewall

Each workspace gets a Kubernetes NetworkPolicy, which matches IP ranges and ports. That is enough for restricted workloads that need only a few known hosts, which are often background jobs such as codebase research or reading logs. It falls apart for dynamic, human-driven AI work. There, the agent installs packages, reads docs, and calls APIs that you cannot list ahead of time, and most of them sit behind CDNs with shared IP addresses that change. You end up allowing whole CDN ranges, or Public internet.

For more advanced rules:

- **ClusterNetworkPolicy** sets rules for the whole cluster that no NetworkPolicy in a namespace can undo. `cluster/` uses it for the optional guardrail on Amazon EKS. See [Guardrail](cluster/README.md#guardrail).
- **Cilium** can match host names (`toFQDNs`) and HTTP requests, so a profile can allow `registry.npmjs.org` or `pypi.org` without their IP ranges.
- **An egress proxy** gives you host name rules and logs on any network plugin. Set `HTTPS_PROXY` in the image, and allow only the proxy in the NetworkPolicy.

### Network ingress

Every profile blocks all ingress. The Coder agent dials out to the Coder server, so the workspace needs no open port. Your options to reach it:

| Option                                    | How it works                                                                                                                                                       | Ingress to open                                                                                                                   |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Through the Coder server (default)        | The web terminal, code-server, `coder ssh`, `coder port-forward`, port sharing, and desktop IDEs relay through the Coder server.                                   | None                                                                                                                              |
| Direct connections                        | Coder connects the client and the workspace peer to peer, which lowers latency. It works only if the client can reach the Pod IP, such as over a VPN into the VPC. | Allow UDP egress to your STUN servers and to the client networks. NetworkPolicy allows the replies.                               |
| A Kubernetes Service, Ingress, or Gateway | Other Pods or users reach a port in the workspace directly, without Coder.                                                                                         | An ingress rule from those Pods or from the ingress controller. Turn off the guardrail, because it blocks ingress from every Pod. |

Use the Coder server when you can. It checks who the user is and what they can access, and it works with every profile. A Service or Ingress skips those checks, so add your own sign-in in front of it. The template creates no Service or Ingress.

### Network egress

| Profile         | Allowed egress                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| Fully isolated  | The Coder server on `coder_egress_port`. No DNS.                                                           |
| GitHub only     | Coder, the GitHub IPv4 ranges on TCP 443 and 80, and DNS to `8.8.8.8` and `1.1.1.1`.                       |
| Public internet | Coder, every public IPv4 address on TCP 443 and 80, and the same DNS. No private ranges or cloud metadata. |

The GitHub ranges are in `shared/defaults.json`. If your `kubernetes` Service points to a public IP (`kubectl get endpoints kubernetes -n default`), Public internet can reach it and the policy check never passes, so set `network_policy_gate = false`. For an air-gapped cluster, mirror the images and providers, and build the image with `CODER_BINARY_URL`.

## Limits

- NetworkPolicy matches IP ranges, so there is no profile for npm or PyPI. Use Public internet, or see [Firewall](#firewall).
- GitHub only and Public internet can still send data out, for example to an attacker's repository or through DNS.
- With the AI Gateway on, code in the workspace can use the owner's Coder session token in `ANTHROPIC_AUTH_TOKEN`.
- A scratch home keeps the agent token in a Pod annotation, so keep read access to the namespace tight. GitHub only pools can clone only public repositories.
- If VPC CNI drops a Pod's rules, the Pod can reach the network for up to 5 s before the check stops it.
- No root, no Docker, IPv4 only. The workspace TTL in Coder is the only stop timer.
