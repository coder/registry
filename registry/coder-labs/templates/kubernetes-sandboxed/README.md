---
display_name: Plain Sandbox (Kubernetes)
description: Run each workspace in a plain Kubernetes Pod behind a host name firewall, with optional gVisor or Kata isolation
icon: ../../../../.icons/kubernetes.svg
verified: false
tags: [kubernetes, container, sandbox, gvisor, kata, ai]
---

# Plain Sandbox (Kubernetes)

Run each workspace in a plain Kubernetes Pod with a persistent home disk. You and your AI agent work in the same Pod, with one Coder agent named `dev`. A NetworkPolicy and a small Squid proxy work as the firewall, so rules can name hosts such as `github.com` or `registry.npmjs.org`. By default the workspace can reach only the Coder server. The template needs no controller and no CRDs, so it works on any cluster with a network plugin that enforces NetworkPolicy.

## Why plain Pods

- **Nothing extra to run:** only Pods, a disk, a Secret, a ConfigMap, a Service, and NetworkPolicies. There is no controller to install or upgrade.
- **Rules by host name:** the proxy allows a list of host names, so a profile can include package registries. A NetworkPolicy alone can match only IP ranges.
- **Any node:** by default the workspace uses the node's normal container runtime. If your nodes have gVisor or Kata, list them in `runtimes` to add kernel isolation.

For a cluster-level warm pool, or if cluster administrators must own the runtime and the network rules, use [agent-sandbox (Kubernetes)](https://registry.coder.com/templates/coder-labs/kubernetes-agent-sandbox) instead.

## Startup speed

With a prebuild, workspaces often start in 3 to 7 seconds, which matters for agents that start a new workspace for each task. To see where the time goes, see [Speed tuning](#speed-tuning).

## Prerequisites

Required:

- **A Kubernetes cluster** with a network plugin that enforces NetworkPolicy, including for traffic to a Service address, and a StorageClass for the home disk.
- **The cluster setup** in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/cluster): a Terraform configuration that creates the namespace and the RBAC. See [`cluster/README.md`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/cluster/README.md).
- **The workspace image**, built from [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/build/Dockerfile).
- **The proxy image**, built from [`build/egress-proxy/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/build/egress-proxy/Dockerfile).
- **Access to the cluster** for the Coder provisioner. The template uses the in-cluster ServiceAccount, or `~/.kube/config` with `use_kubeconfig = true`. With the AI Gateway on, the provisioner also calls the Coder API at the access URL to create the workspace's token.

Optional:

- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.
- **gVisor or Kata** on the nodes, with a RuntimeClass, for kernel isolation. Use gVisor `release-20261019.0` or later. Older releases block on an empty write to a terminal, so the web terminal takes no input.
- **A DaemonSet that pulls the images** on every node.

## Quick start

1. Build both images and push them to your registry. See [Build the images](#build-the-images).
2. Set up the cluster with the Terraform configuration in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/cluster).
3. Write the template variables to a file outside the template directory, and push the template:

   ```sh
   cat > ~/kubernetes-sandboxed.yaml << 'EOF'
   namespace: coder-workspaces
   workspace_image: registry.example.com/coder/workspace:v2.30.0
   proxy_image: registry.example.com/coder/egress-proxy:v1
   coder_egress_cidrs: '["203.0.113.10/32"]'
   EOF
   coder templates push kubernetes-sandboxed -d . --variables-file ~/kubernetes-sandboxed.yaml
   ```

Users pick the network profile and, if you set `runtimes`, the runtime when they create a workspace. They cannot change them later. Each profile except Custom is a preset with `prebuild_instances` prebuilds on the node's container runtime.

Workspaces have no DNS. If the access URL uses a host name, also set `coder_host_ip`. A build fails with a clear message if it is missing.

## Build the images

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_VERSION=2.30.0 \
  -t registry.example.com/coder/workspace:v2.30.0 --push build
docker buildx build --platform linux/amd64 \
  -t registry.example.com/coder/egress-proxy:v1 --push build/egress-proxy
```

- Match `CODER_VERSION` to your Coder server, and rebuild when you upgrade Coder. `CODER_BINARY_URL`, such as `https://coder.example.com/bin/coder-linux-amd64`, copies the binary from your server instead of GitHub.
- `INSTALL_CODE_SERVER=false` and `INSTALL_CLAUDE_CODE=false` leave out the tools. With `INSTALL_CLAUDE_CODE=false`, set `enable_claude_code = false` in the template.
- Use a fixed tag or a digest. The template rejects `:latest`, because with `imagePullPolicy: IfNotPresent` the nodes keep an old copy.

## Architecture

- **For the life of the workspace:** the home disk, the NetworkPolicies, and, except with Fully isolated, the proxy's config and Service.
- **While started:** a Secret with the agent token, the workspace Pod, and the proxy Pod. Stop deletes them and keeps the disk. They are bare Pods, so nothing waits on a Deployment.
- **No DNS:** the workspace resolves no names. The proxy resolves them, and the agent reaches Coder by IP address or by `coder_host_ip`.
- **Policy check:** before the agent starts, the Pod waits until the Kubernetes API server is unreachable, which shows that its NetworkPolicy is in force. It checks again every 5 s and stops the agent if the API server becomes reachable.
- **Pod names:** each name ends in `-pod` after a part that is new for every start. VPC CNI shares rules between Pods with the same name prefix, and deleting an old Pod can drop the rules of a new one.
- **Pods:** run as a non-root user with no capabilities and no ServiceAccount token. The workspace requests 500m CPU and 1 GiB, and the proxy 50m CPU and 64 MiB.
- **Apps:** code-server, and Claude Code, which continues the last conversation in `/home/coder`.

## Speed tuning

In our Amazon EKS test cluster (`m7i.2xlarge` nodes, VPC CNI), from create to a connected agent:

| Workspace                                 | Ready in   |
| ----------------------------------------- | ---------- |
| From a prebuild, any preset               | 3 to 7 s   |
| No prebuild (Custom), or start after stop | about 15 s |
| No prebuild, with a coder/coder clone     | 3 to 6 min |

These all add to the speed:

1. **Prebuilds** (Premium). A claim changes no Pod, so the Pods keep running, and the build takes about 1.6 s. The rest is the agent reconnecting as yours and running the startup scripts. GitHub profiles have already cloned `git_repo_url`.
2. **The image.** [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/build/Dockerfile) adds the Coder agent, code-server, and Claude Code, and the code-server module runs with `offline = true`. So a start downloads nothing, and it also works in Fully isolated. The image is about 800 MB compressed, so pull it ahead of time with a DaemonSet, or the first Pod on a node waits for the pull.
3. **The disk.** Most of a cold start is the EBS volume attaching to the node, 5 to 12 s. A StorageClass with `volumeBindingMode: WaitForFirstConsumer` creates the disk in the node's zone.
4. **The runtime.** gVisor adds little to the start, but slows file-heavy work such as a large `git clone`. Kata boots a VM for each start, and its RuntimeClass overhead needs free CPU on the Kata nodes.
5. **Terraform.** Coder caches modules, but downloads providers on every build unless the provisioner has a provider cache or mirror.

## Firewall

There are two layers, so a bug in one does not open the network:

1. **NetworkPolicy:** the workspace can reach only the Coder server and port 3128 of its own proxy. No DNS, no other Pods, and no cloud metadata.
2. **Squid:** the proxy allows only the profile's host names. It resolves names itself, refuses raw IP addresses and names that resolve to private addresses, and never decrypts HTTPS. Its own NetworkPolicy allows it only public addresses on the profile's ports and DNS.

The proxy is its own Pod, not a sidecar, so nothing in the workspace can change its rules. The workspace gets `HTTPS_PROXY` and `HTTP_PROXY` with the proxy's Service address. curl, git, Go, npm, and pip use them. A program that ignores them cannot connect at all.

Rules by host name work for dynamic, human-driven AI work, where the agent installs packages and reads docs. A rule still allows every path on an allowed host, so an allowed host that stores user content can receive data.

The proxy logs every request, allowed or denied: `kubectl logs <proxy pod>`.

### Network ingress

Every profile blocks all ingress to the workspace. The Coder agent dials out to the Coder server, so the web terminal, code-server, `coder ssh`, port forwarding, and desktop IDEs all relay through Coder. To expose a port to other Pods, add a Service and an ingress rule yourself, and put your own sign-in in front of it.

### Network egress

| Profile                       | Can reach, in addition to Coder                                              |
| ----------------------------- | ---------------------------------------------------------------------------- |
| Fully isolated (default)      | Nothing. No proxy and no DNS.                                                |
| GitHub only                   | GitHub host names on 443                                                     |
| GitHub and package registries | GitHub, npm, the Go module proxy, and PyPI on 443                            |
| Public internet               | Any public host name on 443 and 80. No raw IPs, private ranges, or metadata. |
| Custom                        | The host names and ports that you type. No preset, so a cold start.          |

With Custom, the form shows a list of host names and a choice of ports 443 and 80. `*.example.com` also allows `example.com`. The form rejects IP addresses, names without a dot, `*.com`, and cluster names such as `.svc` or `.local`, and the build checks them again.

## Limits

- No kernel isolation unless you list gVisor or Kata. A kernel bug or container escape reaches the node and the other Pods on it.
- Only HTTPS on 443 and HTTP on 80 pass the proxy. SSH, database ports, and programs that ignore `HTTPS_PROXY` cannot connect. Use Git over HTTPS.
- Public internet and Custom wildcards can still send data out, for example to an attacker's site or in a DNS lookup that the proxy makes.
- Every profile except Fully isolated runs one proxy Pod for each started workspace.
- Each prebuild is a running Pod, so it costs the same as a running workspace.
- With the AI Gateway on, each start gives the workspace a new Coder token with only the `user:read_personal` scope, which the AI Gateway accepts. Code in the workspace can use it for AI requests. Coder cannot revoke it on stop, so it stays valid until the default token lifetime ends, and it shows in the owner's token list as `ai-gateway-<workspace>-<time>`.
- If VPC CNI drops a Pod's rules, the Pod can reach the network for up to 5 s before the check stops it.
- No root, no Docker, IPv4 only.
