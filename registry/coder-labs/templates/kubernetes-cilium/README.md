---
display_name: Cilium Sandbox (Kubernetes)
description: Run each workspace in a Kubernetes Pod behind a Cilium host name firewall, with optional gVisor or Kata isolation
icon: ../../../../.icons/cilium.svg
verified: false
tags: [kubernetes, container, sandbox, firewall, cilium, gvisor, kata, ai]
---

# Cilium Sandbox (Kubernetes)

Run each workspace in a plain Kubernetes Pod with a persistent home disk. You and your AI agent work in the same Pod, with one Coder agent named `dev`. [Cilium](https://cilium.io/) works as the firewall: each workspace gets CiliumNetworkPolicies that allow host names such as `github.com` or `registry.npmjs.org`. By default the workspace can reach only the Coder server.

## Why Cilium

- **Rules by host name, with no proxy:** Cilium's DNS proxy answers only the names that the profile allows, and the workspace can connect only to addresses from those answers. There is no proxy Pod, and programs that ignore `HTTPS_PROXY` work too.
- **Closed from the first packet:** a cluster-wide baseline policy denies all traffic in the namespace. Each workspace's own policies only add what its profile allows. The agent starts with no check or wait for the policy.
- **Flow logs:** Hubble shows every allowed and dropped connection and DNS query, by workspace.

The [Plain Sandbox (Kubernetes)](https://registry.coder.com/templates/coder-labs/kubernetes-sandboxed) template has the same profiles with a Squid proxy, and works on any network plugin that enforces NetworkPolicy. Use this template if your cluster has Cilium, or you can add it to some nodes.

## Prerequisites

Required:

- **A Kubernetes cluster with Cilium** on the nodes for workspaces, with DNS proxy support (the default). On Amazon EKS, Cilium can run in VPC CNI chaining mode on its own node group. See [`cluster/README.md`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-cilium/cluster/README.md).
- **The cluster setup** in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-cilium/cluster): a Terraform configuration that creates the namespace, the RBAC, and the baseline policy.
- **The workspace image**, built from the Plain Sandbox template's [`build/Dockerfile`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-sandboxed/build/Dockerfile). See [Build the image](https://registry.coder.com/templates/coder-labs/kubernetes-sandboxed#build-the-images) there. This template needs no proxy image.
- **Access to the cluster** for the Coder provisioner. The template uses the in-cluster ServiceAccount, or `~/.kube/config` with `use_kubeconfig = true`. With the AI Gateway on, the provisioner also calls the Coder API at the access URL to create the workspace's token.

Optional:

- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.
- **gVisor or Kata** on the Cilium nodes, with a RuntimeClass, for kernel isolation. Cilium enforces the same rules for them.

## Quick start

1. Install Cilium, and apply the Terraform configuration in [`cluster/`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-cilium/cluster).
2. Build the workspace image and push it to your registry.
3. Write the template variables to a file outside the template directory, and push the template:

   ```sh
   cat > ~/kubernetes-cilium.yaml << 'EOF'
   namespace: coder-workspaces
   workspace_image: registry.example.com/coder/workspace:v2.30.0
   EOF
   coder templates push kubernetes-cilium -d . --variables-file ~/kubernetes-cilium.yaml
   ```

Users pick the network profile and, if you set `runtimes`, the runtime when they create a workspace. They cannot change them later. Each profile except Custom is a preset with `prebuild_instances` prebuilds on the node's container runtime.

Set `node_selector` to the labels of the Cilium nodes. The default, `{"coder.com/pool":"cilium"}`, matches [`cluster/cilium-values.yaml`](https://github.com/coder/registry/blob/main/registry/coder-labs/templates/kubernetes-cilium/cluster/cilium-values.yaml). The Pod also tolerates a `NoSchedule` taint with the same key and value. Set it to `{}` only if Cilium runs on every node. A workspace on a node without Cilium has no firewall.

## DNS

Each workspace has one DNS server, `dns_server`, and no cluster search domains. The default, `169.254.169.253`, is the Amazon VPC resolver. On other clouds, use another address that does not change. On Google Cloud, the resolver is the metadata server, which the baseline denies, so use a public resolver such as `8.8.8.8`.

Cilium matches the DNS server by the address that a packet has after Service translation. If CoreDNS runs on nodes without Cilium, that is a CoreDNS Pod address, which changes when CoreDNS restarts. So do not use the kube-dns Service address there.

## Architecture

- **For the life of the workspace:** the home disk and two CiliumNetworkPolicies, `coder-<id>-dns` and `coder-<id>`. Policies add up. The DNS rule is in its own policy because `kubernetes_manifest` sends an empty field as `{}`, and the CRD rejects that for L7 rules.
- **While started:** a Secret with the agent token, and the workspace Pod. Stop deletes them and keeps the disk. The Pod is a bare Pod, so nothing waits on a Deployment.
- **Baseline:** a CiliumClusterwideNetworkPolicy from `cluster/` denies all traffic for every Pod in the namespace, and always denies cloud metadata. The provisioner cannot change it.
- **Pods:** run as a non-root user with no capabilities and no ServiceAccount token. The workspace requests 500m CPU and 1 GiB.
- **Apps:** code-server, Claude Code, and Network check, which tests a few names and addresses from inside the workspace.

## Firewall

| Profile                       | DNS answers and egress, in addition to Coder                                 |
| ----------------------------- | ---------------------------------------------------------------------------- |
| Fully isolated (default)      | Nothing. DNS answers only the Coder host name.                               |
| GitHub only                   | GitHub host names on 443                                                     |
| GitHub and package registries | GitHub, npm, the Go module proxy, and PyPI on 443                            |
| Public internet               | Any public host name on 443 and 80. No raw IPs, private ranges, or metadata. |
| Custom                        | The host names and ports that you type. No preset, so a cold start.          |

- **DNS:** Cilium's DNS proxy refuses every name that the profile does not allow.
- **Egress:** the workspace can connect only to addresses from allowed answers, on the profile's ports. Raw IP addresses that no allowed name resolved to fail.
- **Deny rule:** private, shared, and link-local ranges are always blocked, also when an allowed name resolves to one of them. The DNS server and `coder_egress_cidrs` are the only exceptions.
- **Ingress:** none from other Pods or the network. Cilium still lets the local node connect, for kubelet probes. The Coder agent dials out to the Coder server, so the web terminal, code-server, `coder ssh`, port forwarding, and desktop IDEs all relay through Coder.

With Custom, `*.example.com` allows `example.com` and names one level below it, such as `api.example.com`. Cilium's `*` matches one DNS label. The form rejects IP addresses, names without a dot, `*.com`, and cluster names such as `.svc` or `.local`, and the build checks them again.

To see dropped connections and refused DNS queries:

```sh
kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
  hubble observe --namespace coder-workspaces --verdict DROPPED
```

## Limits

- Rules allow the addresses of allowed names. Many hosts share CDN addresses, so the workspace can reach other sites on those addresses, for example with a different TLS server name. A proxy that does not decrypt HTTPS, such as the one in the Plain Sandbox template, has the same limit.
- HTTPS is encrypted, so the rules allow hosts and ports, not URL paths or HTTP methods. Rules for those need plain HTTP or TLS inspection.
- Public internet and Custom wildcards can still send data out, for example to an attacker's site or in a DNS query.
- There is no rule for STUN, so Coder connections relay through the Coder server and are never direct.
- If the Coder access URL resolves to a private address, set `coder_egress_cidrs`, or the deny rule blocks it.
- No kernel isolation unless you list gVisor or Kata. A kernel bug or container escape reaches the node and the other Pods on it.
- Each prebuild is a running Pod, so it costs the same as a running workspace.
- With the AI Gateway on, each start gives the workspace a new Coder token with only the `user:read_personal` scope, which the AI Gateway accepts. Code in the workspace can use it for AI requests. Coder cannot revoke it on stop, so it stays valid until the default token lifetime ends, and it shows in the owner's token list as `ai-gateway-<workspace>-<time>`.
- No root, no Docker, IPv4 only.
