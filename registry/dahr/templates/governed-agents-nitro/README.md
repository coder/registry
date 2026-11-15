---
display_name: Agent Workspaces on EKS with Nitro Sandboxes
description: Run AI agent workspaces on Amazon EKS in Nitro Sandboxes, behind a default-deny NetworkPolicy and a host name egress proxy
icon: ../../../../.icons/aws.svg
verified: false
tags: [kubernetes, aws, eks, ai, agents, sandbox, security]
---

# Agent Workspaces on EKS with Nitro Sandboxes

Run each workspace as one Pod on Amazon EKS, for AI agents that work on code. With the `isolated-sandbox` RuntimeClass, each workspace Pod runs in its own AWS Nitro Sandbox, a lightweight VM with its own kernel. A default-deny NetworkPolicy and a Squid egress proxy limit where the workspace can connect. EKS Pod Identity can give each workspace its own AWS session with no static keys.

This template creates Coder and Kubernetes resources and, optionally, one EKS Pod Identity association per workspace. It does not create a cluster, a firewall, or images. You supply the cluster, the namespace and its RBAC, the workspace and proxy images, the IAM role, and any AWS network controls. See [Requirements](#requirements).

## How the workspace is isolated

Kernel isolation and network isolation are separate layers. A Nitro Sandbox does not limit network traffic, and a NetworkPolicy does not stop a kernel exploit.

### Kernel isolation

When `sandbox_runtime_class` is `isolated-sandbox`, the workspace Pod sets that RuntimeClass. On EKS Auto Mode, the Pod then runs in a Nitro Sandbox, so code in the workspace does not share a kernel with the node or with other Pods. The VM gets its CPU and memory at boot from the Pod requests, so a Nitro workspace requests its full size of 2 vCPUs and 4 GiB. The variable also accepts other RuntimeClass names, such as `kata-qemu` or `gvisor`. When the value is empty, the Pod uses the node's default runtime and shares the node kernel.

The workspace container runs as UID 1000 with no Linux capabilities, no privilege escalation, the `RuntimeDefault` seccomp profile, and no Kubernetes service account token.

### Network isolation

1. **NetworkPolicy.** The workspace Pod accepts no inbound connections. It can connect out only to the Coder access URL addresses in `coder_egress_cidrs`, its own egress proxy, and the EKS Pod Identity Agent when it has an AWS identity. Your CNI must enforce NetworkPolicy, or this layer does nothing.
2. **No DNS.** The Pod's only name server is `127.0.0.1`, so lookups fail. The template writes the access URL host name to `/etc/hosts` from `coder_host_ip`. The proxy resolves all other names.
3. **Egress proxy.** Squid runs in a separate Pod for each workspace. It accepts only HTTPS `CONNECT` requests to port 443 for the host names in the chosen bundles. It refuses names that resolve to private or link-local addresses, does not decrypt TLS, and logs each request to its container output. Its own NetworkPolicy accepts traffic only from its workspace and allows out only public IPv4 addresses on port 443, plus DNS to the configured servers.
4. **Policy gate.** The Coder agent waits until it cannot connect to the Kubernetes API server. The check then runs every 5 seconds and stops the container if the API server becomes reachable. If the API server remains reachable for 60 seconds, the container exits. This is a useful signal, not proof that every network rule works.
5. **Upstream firewall (optional).** Set `node_pool` to the `key=value` label of a node group whose subnets send traffic through a firewall that you run, such as AWS Network Firewall. Workspace and proxy Pods then select those nodes and tolerate a `NoSchedule` taint with the same key and value. The template does not create or check that firewall.

The proxy Pod does not use the sandbox RuntimeClass. It runs on the node's normal container runtime as UID 31, with a read-only root filesystem and no capabilities.

### AWS identity

With `workspace_role_arn` and `eks_cluster_name` set, each workspace gets its own Kubernetes service account and an EKS Pod Identity association that maps it to the role. The first build of a workspace waits 15 seconds for the association to take effect. The workspace receives `ARTIFACTS_URI` set to `s3://<artifacts_bucket>/workspaces/<service account>/`, and the bucket's regional host name is added to the proxy allowlist. The role policy decides what that session can do. To limit each workspace to its own prefix, scope the policy with the `kubernetes-service-account` session tag that Pod Identity adds.

With `shared_service_account`, every workspace uses one existing service account and an association that you create. All workspaces then share one S3 prefix.

### Models

In the profile that runs Claude Code in the workspace, `ANTHROPIC_BASE_URL` points at Coder AI Gateway, so no model provider key enters the workspace. This requires Coder v2.35 or later with AI Gateway enabled. By default, the build uses the owner's session token once to create a new Coder API token with the `user:read_personal` scope and gives the workspace that token. Set `ai_gateway_token_mode` to `session` to pass the workspace session token instead. See [Limits](#limits) for what each token can do.

## Profiles

The **Agent profile** is set at create and cannot change later. Each profile is a preset with prebuilds.

- **Coder Agents** (default): the agent loop runs in the Coder control plane. The workspace has tools but no model credentials.
- **Claude Code and Kiro in the workspace**: adds code-server, Claude Code through AI Gateway, and the Kiro CLI when its bundle is chosen. Kiro signs in with its device flow and sends model traffic to Kiro's own service, not through AI Gateway.
- **Isolated**: the workspace reaches only Coder. It has no proxy, no AWS identity, and no firewall demo.

## Allowed destinations

In the first two profiles, **Allowed destinations** picks bundles of reviewed host names for the proxy. The template offers bundles for GitHub, npm, PyPI, and Go modules, the Kiro CLI in the Claude Code and Kiro profile, and a demo bundle that opens `example.com`. GitHub is on by default, and so is Kiro where it is offered. A value that is not offered for the profile is ignored. The host names for each bundle are in `local.egress_bundles` in `main.tf`. To add one, add an entry there.

You can change the bundles later in the workspace settings. The next start applies them: a checksum annotation on the proxy Pod restarts Squid with the new list. `extra_allowed_hosts` adds host names to every workspace that has a proxy.

The workspace page shows the runtime class, service account, IAM role, chosen bundles, and the resulting allowlist. The **Firewall demo** app runs sample requests and reports what it can observe. A failed request does not prove which network layer stopped it. Some probes and log hints assume an upstream firewall, an S3 canary object, and log group names from a separate AWS setup, so adjust them to your environment.

## Requirements

### Cluster

- An EKS cluster where `isolated-sandbox` is available. EKS Auto Mode includes this RuntimeClass on Kubernetes 1.36 or later and launches sandbox-capable nodes when needed. On other node groups you install the Nitro Sandbox components yourself. See [Nitro Sandboxes on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/sandboxing.html).
- NetworkPolicy enforcement turned on in the cluster. On EKS Auto Mode, set `enable-network-policy-controller: "true"` in the `amazon-vpc-cni` ConfigMap. Without it, the policy gate stops the workspace agent.
- The EKS Pod Identity Agent, if workspaces get an AWS identity.
- A default StorageClass, or `storage_class_name`, for the home volume. `WaitForFirstConsumer` binding works best.
- x86_64 nodes. The template sets the Coder agent architecture to `amd64`.

Workspace and proxy Pods never schedule on Fargate, which does not enforce NetworkPolicy or support Pod Identity.

### Coder connection

Workspaces reach Coder by IP address only. Give the access URL static IPv4 addresses, for example with a Network Load Balancer, and set `coder_egress_cidrs` to them. If the access URL uses a host name, set `coder_host_ip` to one of those addresses. Connections to the workspace relay through the Coder server, because the Pod accepts no inbound traffic.

### Provisioner access

The provisioner reaches the workspace cluster in one of three ways: in-cluster credentials when Coder runs in the same cluster, `~/.kube/config` with `use_kubeconfig`, or `kube_host`, `kube_ca_certificate`, and `kube_token` for a separate cluster.

The namespace must already exist. Label it for Pod Security `restricted`; both Pods meet that profile. The provisioner identity needs a Role in the namespace that covers every object the template manages, for example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: coder-provisioner
  namespace: coder-workspaces
rules:
  - apiGroups: [""]
    resources:
      [configmaps, persistentvolumeclaims, secrets, serviceaccounts, services]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [apps]
    resources: [deployments]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [networking.k8s.io]
    resources: [networkpolicies]
    verbs: [get, list, watch, create, update, patch, delete]
```

For per-workspace Pod Identity, the provisioner also needs AWS credentials that can create, read, tag, and delete Pod Identity associations on the cluster and pass the workspace role. The workspace role must trust `pods.eks.amazonaws.com` for `sts:AssumeRole` and `sts:TagSession`. Bind the namespace Role to the provisioner identity with a RoleBinding.

### Images

You build and host both images. Use a fixed tag or a digest; the template rejects `:latest`. The [example Dockerfiles](../../../coder-labs/templates/kubernetes-sandboxed/build/) in this registry provide a starting point, but they do not include every tool this template uses.

The workspace image needs:

- The Coder binary at `/usr/local/bin/coder`, matching your Coder server version, since the workspace cannot download it.
- `bash`, `curl`, and `awk` for the policy gate, and a user with UID 1000.
- For the Claude Code and Kiro profile: code-server under `/opt/code-server`, Claude Code at `/opt/claude/bin/claude`, `tmux`, and `kiro-cli` on the `PATH`.
- `git` to clone `git_repo_url`, and the AWS CLI for the firewall demo's S3 checks.

The proxy image needs Squid that starts with `/etc/squid-conf/squid.conf`, where the template mounts its configuration, and runs as UID and GID 31 with a read-only root filesystem.

## Push the template

Create a variables file outside any repository. The values below are placeholders.

```yaml
workspace_image: 123456789012.dkr.ecr.us-west-2.amazonaws.com/agent-workspace:v1
proxy_image: 123456789012.dkr.ecr.us-west-2.amazonaws.com/egress-proxy:v1
aws_region: us-west-2
coder_egress_cidrs: '["203.0.113.10/32","203.0.113.11/32"]'
coder_host_ip: 203.0.113.10
sandbox_runtime_class: isolated-sandbox
namespace: coder-workspaces
eks_cluster_name: example-cluster
workspace_role_arn: arn:aws:iam::123456789012:role/example-workspace-role
artifacts_bucket: example-agent-artifacts
```

Then push from this directory:

```sh
coder templates push governed-agents-nitro -d . --variables-file ~/governed-agents-nitro.yaml
```

If the provisioner uses `kube_token`, add it to this file only on the machine you push from. Set its permissions to `600` and do not commit it.

Prebuilds need Coder Premium. By default each of the three presets keeps one prebuilt workspace running; set `prebuild_instances` to `0` to turn them off.

## Limits

- **Allowed hosts can still receive data.** Squid sees only the host name, not the path or content, and so does a firewall that filters on the TLS server name. An agent can push to any GitHub repository its credentials allow. Limit writes with scoped Git credentials and organization settings.
- **Without an upstream firewall,** the proxy connects from the node to any public IPv4 address that an allowed name resolves to. There is no second allowlist and no DNS filtering beyond your resolver, so the demo bundle reaches `example.com`. Setting `node_pool` only schedules on labeled nodes. It does not configure or verify network routing.
- **The proxy is not in a Nitro Sandbox.** It shares the node kernel with other Pods on its node. Its NetworkPolicy and Squid configuration limit what it accepts and where it connects.
- **NetworkPolicy depends on the CNI.** The policy gate checks only that the Kubernetes API server is unreachable. It does not prove every rule is in force.
- **The scoped token is not limited to AI Gateway.** A `user:read_personal` token also works with other Coder API endpoints that allow that scope, from any network that reaches Coder. Any process in the workspace can read it. It lives for `ai_gateway_token_lifetime_hours`, Coder does not revoke it on stop, and each start creates a new one. Keep the lifetime close to the template's autostop time. The `session` mode token has full API access for the owner, but Coder deletes it on stop.
- **Kiro bypasses AI Gateway.** AI Gateway does not record Kiro prompts. The proxy log records Kiro's connections.
- **HTTPS on port 443 only.** SSH, plain HTTP, and other ports do not work through the proxy. Use Git over HTTPS. IPv4 only.
- **Fixed size in a Nitro Sandbox.** CPU and memory are set at boot. Check allocatable resources on your sandbox nodes before you change the size in `main.tf`.

The egress proxy, policy gate, and scoped token patterns are adapted from [coder-labs/kubernetes-sandboxed](../../../coder-labs/templates/kubernetes-sandboxed/) (Apache-2.0).
