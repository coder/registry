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

When `sandbox_runtime_class` is `isolated-sandbox`, the workspace Pod sets that RuntimeClass. On EKS Auto Mode, the Pod then runs in a Nitro Sandbox, so code in the workspace does not share a kernel with the node or with other Pods. The VM gets its CPU and memory at boot from the Pod requests, so a Nitro workspace requests its full size of 2 vCPUs and 4 GiB. When the value is empty, the Pod uses the node's default runtime and shares the node kernel.

The workspace container runs as UID 1000 with no Linux capabilities, no privilege escalation, the `RuntimeDefault` seccomp profile, and no Kubernetes service account token.

### Network isolation

1. **NetworkPolicy.** The workspace Pod accepts no inbound connections. It can connect out only to the Coder access URL addresses in `coder_egress_cidrs`, its own egress proxy, and the EKS Pod Identity Agent when it has an AWS identity. Your CNI must enforce NetworkPolicy, or this layer does nothing.
2. **No DNS.** The Pod's only name server is `127.0.0.1`, so lookups fail. The template writes the access URL host name to `/etc/hosts` from `coder_host_ip`. The proxy resolves all other names.
3. **Egress proxy.** Squid runs in a separate Pod for each workspace. It accepts only HTTPS `CONNECT` requests to port 443 for the host names in the chosen bundles. It refuses names that resolve to private or link-local addresses, does not decrypt TLS, and logs each request to its container output. Its own NetworkPolicy accepts traffic only from its workspace and allows out only public IPv4 addresses on port 443, plus DNS to the configured servers.
4. **Policy gate.** The Coder agent waits until 3 connections in a row to the Kubernetes API server fail, each with a 1 second timeout, so one slow connection cannot open the gate. The check then runs every 5 seconds and stops the container if the API server becomes reachable. If the API server remains reachable for 60 seconds, the container exits. This is a readiness check, not a security boundary: it runs as the workspace user, who can kill it, and any failed connection counts as closed, including an API server outage. Enforcement comes from the CNI.
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

In the first two profiles, **Allowed destinations** picks bundles of reviewed host names for the proxy. The template offers bundles for GitHub, npm, PyPI, and Go modules, the Kiro CLI in the Claude Code and Kiro profile, and a demo bundle that opens `example.com`. GitHub is on by default. Kiro is opt-in, because it sends model traffic outside AI Gateway. The form offers only the bundles of the chosen profile; a bundle the profile does not offer, passed from the CLI, fails the build. The host names for each bundle are in `local.egress_bundles` in `main.tf`. To add one, add an entry there.

You can change the bundles later in the workspace settings. The next start applies them: a checksum annotation on the proxy Pod restarts Squid with the new list. `extra_allowed_hosts` adds host names to every workspace that has a proxy.

The workspace page shows the runtime class, service account, IAM role, chosen bundles, and the resulting allowlist. The **Firewall demo** app runs sample requests and reports what it can observe. A failed request does not prove which network layer stopped it. Some probes and log hints assume an upstream firewall, an S3 canary object, and log group names from a separate AWS setup, so adjust them to your environment.

## Requirements

### Cluster

- An EKS cluster where `isolated-sandbox` is available. EKS Auto Mode includes this RuntimeClass on Kubernetes 1.36 or later and launches sandbox-capable nodes when needed. On other node groups you install the Nitro Sandbox components yourself. See [Nitro Sandboxes on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/sandboxing.html).
- NetworkPolicy enforcement turned on in the cluster. On EKS Auto Mode, set `enable-network-policy-controller: "true"` in the `amazon-vpc-cni` ConfigMap. Without it, the policy gate stops the workspace agent.
- Recommended on EKS Auto Mode: `networkPolicy: DefaultDeny` on the NodeClass of the workspace nodes. A Pod that no NetworkPolicy selects then has no traffic, so a new Pod is closed until its policy lands, and a workspace whose policy is deleted loses its egress instead of gaining it. The default, `DefaultAllow`, leaves both cases open.
- The EKS Pod Identity Agent, if workspaces get an AWS identity.
- A default StorageClass, or `storage_class_name`, for the home volume. `WaitForFirstConsumer` binding works best.
- x86_64 nodes. The template sets the Coder agent architecture to `amd64`.

Workspace and proxy Pods never schedule on Fargate, which does not enforce NetworkPolicy or support Pod Identity.

### Coder connection

Workspaces reach Coder by IP address only. Give the access URL static IPv4 addresses, for example with a Network Load Balancer, and set `coder_egress_cidrs` to them. If the access URL uses a host name, set `coder_host_ip` to one of those addresses. Connections to the workspace relay through the Coder server, because the Pod accepts no inbound traffic.

### Provisioner access

The provisioner reaches the workspace cluster with in-cluster credentials when Coder runs in the same cluster, or with `~/.kube/config` when `use_kubeconfig` is true.

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

Variables you leave out of the file keep their value from the previous version. To clear one, pass it explicitly, for example `--variable shared_service_account=`.

Prebuilds need Coder Premium. By default each of the three presets keeps one prebuilt workspace running; set `prebuild_instances` to `0` to turn them off.

## Stop a workspace from outside

1. `coder stop <owner>/<workspace>` deletes the Pods, which ends every process and connection and keeps the home volume.
2. To keep a running Pod for forensics, cut its network instead. With VPC CNI 1.21 or later, an Admin-tier `ClusterNetworkPolicy` that denies all traffic for Pods with a label such as `coder.com/quarantine=true` takes effect before every NetworkPolicy; label the workspace and proxy Pods to apply it. It blocks new connections only: in testing, the agent's open connection to Coder and `coder ssh` over it kept working. Stop the workspace once you have the evidence.
3. Suspend the user, revoke their tokens, and keep the proxy, firewall, and AI Gateway logs.

Do not delete the workspace NetworkPolicy to stop a workspace. Without `DefaultDeny` on the node, that opens the Pod.

## Firewall demo

The **Firewall demo** app runs sample requests and names the result of each. Unauthenticated GitHub writes return HTTP 401, which shows only that the network let them through. With `github_external_auth_id` set to a Coder external auth provider, more rows use the workspace owner's linked GitHub credential: who am I, a branch in a repository of `github_org`, a branch in the owner's own repository, and a gist. The write requests are well formed but cannot succeed (a branch at a commit that does not exist, a gist with an empty file), so HTTP 403 means the credential may not write, 422 means it may, and nothing is created. Empty request bodies are not a valid test, because GitHub answers some of them with 422 before it checks permission.

## Limits

- **Allowed hosts can still receive data.** Squid sees only the host name, not the path or content, and so does a firewall that filters on the TLS server name. An agent can push to any GitHub repository its credentials allow. Limit writes with scoped Git credentials and organization settings.
- **Without an upstream firewall,** the proxy connects from the node to any public IPv4 address that an allowed name resolves to. There is no second allowlist and no DNS filtering beyond your resolver, so the demo bundle reaches `example.com`. Setting `node_pool` only schedules on labeled nodes. It does not configure or verify network routing.
- **The proxy is not in a Nitro Sandbox.** It shares the node kernel with other Pods on its node. Its NetworkPolicy and Squid configuration limit what it accepts and where it connects.
- **NetworkPolicy depends on the CNI.** The policy gate checks only that the Kubernetes API server is unreachable. It does not prove every rule is in force.
- **The scoped token is not limited to AI Gateway.** A `user:read_personal` token also works with other Coder API endpoints that allow that scope, from any network that reaches Coder. Any process in the workspace can read it. Each start revokes the workspace's earlier tokens with the `coder` CLI on the provisioner, so only the newest is valid. Coder gives stop builds no owner credentials, so the last token stays valid for up to `ai_gateway_token_lifetime_hours` (8 by default) after the workspace stops. Keep the lifetime close to the template's autostop time. Like the owner session token, the scoped token is stored unencrypted in Terraform state, which template admins can read. The `session` mode token has full API access for the owner, but Coder deletes it on stop.
- **Kiro bypasses AI Gateway.** AI Gateway does not record Kiro prompts, so its bundle is opt-in. The proxy log records Kiro's connections.
- **AWS credentials work outside your network.** Pod Identity credentials are ordinary temporary credentials. If an agent copied them to an allowed host that accepts uploads, they would work from anywhere until they expire. Add a condition to the workspace role's policy: `aws:SourceVpce` with your S3 gateway endpoint's ID for S3, or `aws:SourceIp` with your NAT gateway addresses for services reached through it. `aws:SourceVpc` and `aws:SourceVpce` are set only on requests through a VPC endpoint.
- **HTTPS on port 443 only.** SSH, plain HTTP, and other ports do not work through the proxy. Use Git over HTTPS. IPv4 only.
- **Fixed size in a Nitro Sandbox.** CPU and memory are set at boot. Check allocatable resources on your sandbox nodes before you change the size in `main.tf`.
- **Disk in a Nitro Sandbox.** The workspace container has an 8 GiB ephemeral-storage limit and the proxy 256 MiB. Inside a sandbox the kubelet cannot measure disk use, so the 2 GiB `/tmp` size limit is not enforced there. The sandbox gets a disk the size of the limit instead, shared by `/` and `/tmp`, and writes past it fail with `No space left on device`. The home volume is separate.
- **Network stops block new connections only.** A quarantine policy or a deleted NetworkPolicy leaves established connections open, including the agent's connection to Coder. Use `coder stop` to end them.

The egress proxy, policy gate, and scoped token patterns are adapted from [coder-labs/kubernetes-sandboxed](../../../coder-labs/templates/kubernetes-sandboxed/) (Apache-2.0).
