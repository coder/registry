---
display_name: Kubernetes (agent-sandbox)
description: Run each workspace in an agent-sandbox Sandbox with gVisor or Kata isolation and a NetworkPolicy firewall
icon: ../../../../.icons/agent-sandbox.svg
verified: false
tags: [kubernetes, agent-sandbox, sandbox, gvisor, kata, ai]
---

# Kubernetes agent-sandbox

Run each workspace in a Sandbox from [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox), a Kubernetes SIG project. You and your AI agent work in the same sandbox, with one Coder agent named `dev`. The sandbox runs under gVisor or a Kata microVM, so it does not share the node kernel. A Kubernetes NetworkPolicy works as the firewall. By default the workspace can reach only the Coder server. Code in the workspace can still use that connection, for example with the Coder session token that the AI Gateway needs (see [Limits](#limits)).

The image has the Coder agent, code-server, and Claude Code built in, so a workspace downloads nothing at start. Claude Code reaches Anthropic through the Coder AI Gateway, so it works with no internet access.

## Prerequisites

- **Cluster**: a Kubernetes cluster with a network plugin that enforces NetworkPolicy, and a StorageClass for the home disk.
- **agent-sandbox**: the controller and the extensions, v1.0.4 or later. See item 3 of the [Fast startup checklist](#fast-startup-checklist).
- **RuntimeClasses**: `gvisor`, and `kata-qemu` and `kata-clh` if you offer Kata. See item 5 of the checklist.
- **Namespace and permissions**: [`cluster/rbac.yaml`](cluster/rbac.yaml) creates the example namespace `coder-workspaces` and a Role and RoleBinding for the Coder provisioner ServiceAccount `coder/coder`. The Role covers Sandboxes, SandboxClaims, PersistentVolumeClaims, Secrets, and NetworkPolicies in that namespace only. The file also has a ClusterRole for reading CRDs, in a comment. Add it if a build fails with a `customresourcedefinitions ... is forbidden` error.
- **Scratch homes**: the SandboxTemplates in [`cluster/sandbox-templates.yaml`](cluster/sandbox-templates.yaml) and the warm pools in [`cluster/warm-pools.yaml`](cluster/warm-pools.yaml). Persistent homes do not need them.
- **Authentication**: the template uses the in-cluster ServiceAccount when the Coder provisioner runs in the cluster. Set `use_kubeconfig = true` to use `~/.kube/config` on the Coder host instead. For other methods, see the [provider docs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication).
- **Image**: an image built from [`build/Dockerfile`](build/Dockerfile). See [Build the image](#build-the-image).
- **Coder Premium**, for prebuilds and the AI Gateway. Without it, set `prebuild_instances = 0` and `enable_ai_gateway = false`, and give Claude Code another way to sign in.

The files in `cluster/` use example values. Replace them before you apply the files:

```sh
cd cluster
sed -i \
  -e 's/coder-workspaces/<namespace>/g' \
  -e 's#registry.example.com/coder/workspace:v2.30.0#<workspace_image>#g' \
  -e 's#https://coder.example.com#<access URL>#g' \
  -e 's#203.0.113.10/32#<Coder server CIDR>#g' \
  -e 's/port: 443$/port: <Coder port>/' \
  *.yaml
kubectl apply -f rbac.yaml -f sandbox-templates.yaml -f warm-pools.yaml
```

## Build the image

Build `build/Dockerfile` and push it to a registry that your nodes can pull from:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg CODER_VERSION=2.30.0 \
  -t registry.example.com/coder/workspace:v2.30.0 --push build
```

- `CODER_VERSION` downloads the Coder binary from the GitHub release.
- `CODER_BINARY_URL` copies the binary from somewhere else instead, such as your own server: `https://coder.example.com/bin/coder-linux-amd64`. Use this for development builds or when the build cannot reach GitHub.
- The agent version should match your Coder server. Rebuild the image when you upgrade Coder.
- `INSTALL_CODE_SERVER=false` and `INSTALL_CLAUDE_CODE=false` leave out the tools.

The workspace runs `/usr/local/bin/coder agent` from the image. It does not run the agent init script, which downloads the binary.

Use a fixed tag or a digest. The template rejects `:latest`, because `imagePullPolicy: IfNotPresent` would keep an old copy on the nodes.

## Fast startup checklist

1. **Pre-baked image.** The agent, code-server, and Claude Code are in the image, so a start downloads nothing. The Pod uses `imagePullPolicy: IfNotPresent`. The image is large, about 800 MB compressed, so the first Pod on a node can wait a minute for the pull. To pull it ahead of time, run a DaemonSet with the image on every node. An init container that runs `true`, and a pause container, are enough.
2. **Prebuilds and presets** (Premium). The template has one preset per network profile, each with gVisor and a persistent home. Each keeps `prebuild_instances` prebuilt workspaces (default 1). A claim reuses the running Sandbox and its disk. Coder keeps the agent token, so the Pod does not change. In our test, a claimed prebuild was ready in 5.1 to 5.9 s. A new Kata QEMU workspace without a prebuild took 18.7 s, most of it to create and attach the new disk and boot the VM. A workspace whose parameters match a preset also gets a prebuild, even when the user picks no preset. Each prebuild costs as much as a running workspace. Add presets for the Kata options if your users pick them often.
3. **The agent-sandbox controller.** Install v1.0.4 with the extensions, which add SandboxTemplate, SandboxClaim, and SandboxWarmPool:

   ```sh
   kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.4/sandbox-with-extensions.yaml
   ```

   The default settings suit one warm pool. With more pools, add these flags to the controller Deployment, so that the pools refill at the same time:

   ```sh
   kubectl -n agent-sandbox-system patch deployment agent-sandbox-controller --type json -p '[
     {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--sandbox-warm-pool-concurrent-workers=3"},
     {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--api-connections=4"},
     {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--separate-watch-connection=true"}
   ]'
   ```

   Set `--sandbox-warm-pool-concurrent-workers` to the number of pools. These flags make refills faster. Claims were already fast, 50 to 80 ms. The template puts only annotations on a claimed Pod, so you do not need to change the `allowed-label-domains` setting. See the agent-sandbox `docs/performance-tuning.md` for all flags.

4. **A SandboxWarmPool**, for scratch homes. [`cluster/warm-pools.yaml`](cluster/warm-pools.yaml) has one pool per runtime, each with 1 idle sandbox. A scratch workspace claims an idle sandbox, and the pool boots a new one. In our test, a scratch workspace was ready in 3.5 to 6.5 s. Each idle sandbox reserves the Pod's requests (500m CPU and 1 GiB) plus the RuntimeClass overhead (Kata: 250m CPU and 130 to 320 MiB). In our test cluster, one idle sandbox filled a 2 CPU, 4 GiB slot on an `m7i.2xlarge` node: about $0.058 an hour, or $42 a month, at us-east-1 on-demand prices. An idle sandbox also uses a little CPU for the runtime and for the loop that waits for the token, which checks 4 times a second. Use `kubectl top pod` to see it on your nodes. Set `replicas` to the number of scratch workspaces that start at about the same time, and to 0 for runtimes that you do not use. The pools use `updateStrategy.type: Recreate`, so they replace idle sandboxes when you change a SandboxTemplate.
5. **RuntimeClasses.**
   - gVisor runs on any Linux node. Install `runsc` and its containerd shim on each node, add a `runsc` runtime to the containerd config, and create a RuntimeClass named `gvisor` with `handler: runsc`. See the [gVisor containerd guide](https://gvisor.dev/docs/user_guide/containerd/quick_start/). On GKE, GKE Sandbox provides the `gvisor` RuntimeClass.
   - Kata needs `/dev/kvm` on the node: a bare metal node, or a VM with nested virtualization. On EC2, C7i, M7i, R7i, C8i, M8i, and R8i instances support nested virtualization when they start with `CpuOptions.NestedVirtualization=enabled`. eksctl cannot set this, so use an EC2 launch template for the node group. Install Kata with the [kata-deploy Helm chart](https://github.com/kata-containers/kata-containers/blob/main/tools/packaging/kata-deploy/helm-chart/README.md):

     ```sh
     helm install kata-deploy oci://ghcr.io/kata-containers/kata-deploy-charts/kata-deploy \
       --version 4.2.0 -n kube-system -f kata-values.yaml
     ```

     With these values, the chart installs only the QEMU and Cloud Hypervisor shims, and only on nodes labeled `coder.com/runtime=kata`:

     ```yaml
     nodeSelector:
       coder.com/runtime: kata
     shims:
       disableAll: true
       qemu:
         enabled: true
       clh:
         enabled: true
     runtimeClasses:
       enabled: true
       createDefault: false
     ```

     The `kata-qemu` and `kata-clh` RuntimeClasses from the chart have a `scheduling.nodeSelector`. Kubernetes then places Kata Pods on the Kata nodes without a nodeSelector in the template.

   - On a cold start, gVisor added about 0.2 s over a normal container, Kata Cloud Hypervisor about 1.5 s, and Kata QEMU about 2.6 s. A warm pool or a prebuild hides this time.

6. **Terraform init.** Coder caches modules by default. Providers are downloaded on every build unless the provisioner has them. Bake a provider cache or a `filesystem_mirror` into the provisioner image, with `TF_PLUGIN_CACHE_DIR` or a Terraform CLI config file. coder/coder PRs [#29825](https://github.com/coder/coder/pull/29825) and [#29827](https://github.com/coder/coder/pull/29827) skip `terraform init` and reuse the lock file. They are still open today. With them, `terraform init` went from about 3.3 s to near zero. Only template versions pushed after an upgrade get the gain, so push your templates again after you upgrade Coder.
7. **Coder server resources.** The Helm chart's default CPU limit of 2 slowed builds through CPU throttling. With 4 CPUs, each start was about 2.4 s faster. Run enough provisioners for your prebuilds and for users who start at the same time.
8. **Disk.** Use a StorageClass with `volumeBindingMode: WaitForFirstConsumer`, so the disk is created in the zone of the node. When a workspace starts on another node, moving the EBS volume adds 5 to 10 s. In our test, a start after a stop took 7.5 to 12 s. Scratch homes use no disk.
9. **A network plugin that enforces NetworkPolicy.** Without one, the policies do nothing, and the policy gate keeps the agent from starting. Notes for Amazon VPC CNI with the network policy agent (tested with v1.4.0 in `standard` mode):
   - A new Pod can reach everything for up to about 30 s, until its policy is applied. Before the agent starts, the container waits until a TCP connection to the Kubernetes API server fails. If it still connects after about 60 s, the container exits and restarts. In our test the wait took about 3 s.
   - A Pod can also lose its rules while it runs (see the next item). So after start, the container checks the API server every 5 s. If a connection succeeds, it stops the agent and exits, and Kubernetes restarts it, which runs the start check again.
   - The policy agent groups Pods by their name without the last `-` part, and Pods in a group share rules. Deleting an old Pod of a group can remove the rules of a new Pod in the same group. So each start gets a new Sandbox name that ends in `-pod`, after a part that is new for each start.
   - All Pods of one warm pool on one node are in one group. This is why a scratch home allows only Fully isolated.
   - The kubelet port on the Pod's own node is always reachable. It answers 401 without credentials.

## Parameters

| Parameter                               | Options                                                                | Notes                                                                                                                                                          |
| --------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network isolation (`network_isolation`) | Fully isolated (default), GitHub only, Public internet                 | See [Network egress](#network-egress). You cannot change it after create.                                                                                      |
| Kernel isolation (`runtime`)            | gVisor (default), Kata microVM (QEMU), Kata microVM (Cloud Hypervisor) | The RuntimeClass of a persistent home, or the warm pool `coder-<runtime>` of a scratch home.                                                                   |
| Home directory (`home`)                 | Persistent (default), Scratch                                          | Persistent: a disk at `/home/coder`, kept on stop. Scratch: a booted sandbox from the warm pool, deleted on stop. Scratch is offered only with Fully isolated. |

Presets:

| Preset                               | Prebuilds                          |
| ------------------------------------ | ---------------------------------- |
| Fully isolated, gVisor (default)     | `prebuild_instances`               |
| GitHub only, gVisor                  | `prebuild_instances`               |
| Public internet, gVisor              | `prebuild_instances`               |
| Fully isolated, scratch home, gVisor | None. The warm pool keeps it fast. |

## Variables

The Scratch column shows which variables also apply to a scratch home. For a scratch home, the image, the Coder address, the NetworkPolicy, and the policy check come from `cluster/sandbox-templates.yaml`. Keep the two in line.

| Variable              | Default | Scratch | Description                                                                                                                                                                                                                                                                                                                          |
| --------------------- | ------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `namespace`           | none    | Yes     | The namespace for workspaces. It must exist, with the Role from `cluster/rbac.yaml`.                                                                                                                                                                                                                                                 |
| `workspace_image`     | none    | No      | The image built from `build/Dockerfile`, with a tag other than `:latest`, or a digest.                                                                                                                                                                                                                                               |
| `coder_egress_cidrs`  | none    | No      | The IPv4 CIDR ranges of the Coder server, for example `["203.0.113.10/32"]`. Every profile allows them.                                                                                                                                                                                                                              |
| `coder_egress_port`   | `443`   | No      | The TCP port of the access URL.                                                                                                                                                                                                                                                                                                      |
| `coder_host_ip`       | `""`    | No      | The IPv4 address of the access URL host. Fully isolated blocks DNS, so if the access URL uses a host name, the template adds this address to `/etc/hosts`. A persistent build with Fully isolated fails if the access URL uses a host name and this is empty. For a scratch home, set `hostAliases` in the SandboxTemplates instead. |
| `home_disk_size`      | `10`    | No      | The size of the persistent home disk, in GiB.                                                                                                                                                                                                                                                                                        |
| `storage_class_name`  | `""`    | No      | The StorageClass of the home disk. Empty uses the cluster default.                                                                                                                                                                                                                                                                   |
| `prebuild_instances`  | `1`     | No      | Prebuilt workspaces per persistent preset (Premium). `0` turns them off.                                                                                                                                                                                                                                                             |
| `git_repo_url`        | `""`    | No      | A Git repository to clone into `/home/coder`, for example `https://github.com/coder/coder`. Only GitHub only and Public internet workspaces clone it. A prebuild clones it before a claim, so a claim does not wait.                                                                                                                 |
| `enable_ai_gateway`   | `true`  | Yes     | Send Claude Code requests through the Coder AI Gateway (Premium).                                                                                                                                                                                                                                                                    |
| `network_policy_gate` | `true`  | No      | Start the agent only after a connection to the Kubernetes API server fails, and stop it if one succeeds later. Turn it off only if a profile can reach the API server (see [Limits](#limits)).                                                                                                                                       |
| `use_kubeconfig`      | `false` | Yes     | Use `~/.kube/config` on the Coder host instead of the in-cluster ServiceAccount.                                                                                                                                                                                                                                                     |

## How the sandbox works

With a **persistent home**, Terraform creates:

- A PersistentVolumeClaim for `/home/coder`. Coder owns it, so it stays when the workspace stops.
- A NetworkPolicy that denies all ingress and allows egress to the Coder server, plus the ranges of the profile.
- A Secret with the agent token, and a Sandbox. The agent-sandbox controller creates the Pod from the Sandbox. Stop deletes the Sandbox, the Pod, and the Secret, but not the disk.

With a **scratch home**, Terraform creates only a SandboxClaim on the warm pool of the runtime. agent-sandbox hands the claim an idle, booted Pod and adds the claim's `coder.com/agent-token` annotation to it. The Pod reads the token through the downward API and starts the agent. The NetworkPolicy comes from the SandboxTemplate and allows only the Coder server. The claimed Pod gets only annotations, not the `com.coder.workspace.id` label, on purpose: labels on a claim need a domain from the controller's `allowed-label-domains` setting, and annotations do not. The SandboxClaim itself has the label. Stop deletes the claim and the Pod, with everything in `/home/coder`.

Both kinds of Pod:

- Run as user and group 1000, with `fsGroup: 1000` and `fsGroupChangePolicy: OnRootMismatch`, so a start does not change the owner of every file on the disk.
- Drop all Linux capabilities, set `allowPrivilegeEscalation: false`, use the `RuntimeDefault` seccomp profile, and have no Kubernetes ServiceAccount token.
- Use `8.8.8.8` and `1.1.1.1` as DNS servers, not the cluster DNS. Fully isolated blocks them, so lookups fail fast.
- Copy `/etc/skel` into a new, empty home, so the shell gets the image's dotfiles.
- Run `/usr/local/bin/coder agent` from the image, with `CODER_AGENT_URL` set to the access URL and `CODER_AGENT_AUTH=token`. The agent starts only after the policy check passes, and the check runs again every 5 s (see item 9 of the checklist).
- Have a termination grace period of 2 s, so a stop frees the home disk quickly.
- Request 500m CPU and 1 GiB of memory, with a limit of 2 CPUs and 4 GiB. Change `local.resources` in `main.tf` and the SandboxTemplates together.

The workspace has two apps:

- code-server, from the image (`offline = true`).
- Claude Code, with the auto-updater turned off. The app runs `claude --continue || claude`: it continues the last conversation in `/home/coder`, or starts a new one if there is none. If the image has `tmux`, the app runs Claude in a tmux session named `claude`, so the session survives a closed browser tab. The image from `build/Dockerfile` does not have tmux. Add it to the image if you want this. With a scratch home, the conversation history is lost on stop.

## Network egress

These are the endpoints that the template, the image build, and the workspace contact.

**The template (Coder provisioner):**

- The Kubernetes API server.
- `registry.coder.com`, for the code-server module. Coder caches modules for each template version.
- `registry.terraform.io` and `releases.hashicorp.com`, for the `coder/coder` and `hashicorp/kubernetes` providers, unless the provisioner has a provider mirror.

**The image build:**

- Docker Hub, for `codercom/enterprise-base:ubuntu`.
- `github.com`, for the Coder release (`CODER_VERSION`), or your `CODER_BINARY_URL`.
- `code-server.dev`, `api.github.com`, and `github.com`, for code-server.
- `claude.ai` and `downloads.claude.ai`, for Claude Code.

**The cluster:**

- Your image registry, to pull the workspace image.
- `registry.k8s.io`, for the agent-sandbox controller image.
- The gVisor and Kata release hosts, if you install them from the internet (`storage.googleapis.com` for gVisor, `ghcr.io` and `quay.io` for kata-deploy).

**The workspace:**

| Profile         | Allowed egress                                                                                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fully isolated  | `coder_egress_cidrs` on `coder_egress_port`. No DNS. The agent, the terminal, apps, and the AI Gateway all use this connection.                                         |
| GitHub only     | Coder, the GitHub IPv4 ranges `140.82.112.0/20`, `143.55.64.0/20`, `185.199.108.0/22`, and `192.30.252.0/22` on TCP 443 and 80, and DNS to `8.8.8.8` and `1.1.1.1`.     |
| Public internet | Coder, `0.0.0.0/0` on TCP 443 and 80 except `10.0.0.0/8`, `100.64.0.0/10`, `169.254.0.0/16`, `172.16.0.0/12`, and `192.168.0.0/16`, and DNS to `8.8.8.8` and `1.1.1.1`. |

No profile allows UDP other than DNS, so STUN fails, and connections to the workspace relay through the Coder server.

The GitHub ranges come from `https://api.github.com/meta`. They cover `github.com`, `api.github.com`, `codeload.github.com`, and `raw.githubusercontent.com` when DNS resolves from the US. To refresh them, run the command in the comment above `github_cidrs` in `main.tf`.

The policy check needs a destination that every profile blocks, and it uses the Kubernetes API server. On most clusters the `kubernetes` Service points to private addresses, which every profile blocks. On some clusters, for example some GKE and Azure Kubernetes Service setups, it points to a public IP. Public internet then allows it, so the check never passes and the agent never starts. Find the address with `kubectl get endpoints kubernetes -n default`. If it is public, set `network_policy_gate = false`, or add the address to the `except` list of the Public internet profile in `main.tf`.

For a restricted or air-gapped cluster:

- Mirror the images (workspace, agent-sandbox controller, gVisor, kata-deploy) to an internal registry.
- Build the image with `CODER_BINARY_URL` set to your Coder server.
- Give the provisioner a provider mirror, and make `registry.coder.com` reachable or vendor the module into the template.
- If the access URL resolves only on an internal DNS server, change `local.dns_servers` in `main.tf` and the `dnsConfig` in the SandboxTemplates, or use `coder_host_ip`.

## Limits

- Under gVisor, typing in the web terminal does nothing with current Coder agents. The agent passes empty resize messages to the terminal, and gVisor blocks on that empty write, so all later input waits behind it. `coder ssh` and Kata are not affected. Until the agent skips empty writes, use Kata or `coder ssh` if you need the web terminal.
- A NetworkPolicy matches IP ranges, not host names. So there is no profile for package registries such as npm or PyPI, which use shared CDNs without fixed ranges. Use Public internet for them.
- Public internet allows every public host, so code in the workspace can send data to any public website.
- GitHub only still lets code in the workspace send data out: it can push to any GitHub repository or gist that a token it has can write to, including one that an attacker owns. A NetworkPolicy cannot limit which repositories it uses.
- GitHub only and Public internet allow DNS to `8.8.8.8` and `1.1.1.1`. DNS queries can carry small amounts of data to any domain.
- With the AI Gateway on, the workspace has the owner's Coder session token in `ANTHROPIC_AUTH_TOKEN`. Code in the workspace, including an AI agent, can use that token through the allowed Coder connection to call the Coder API as the owner, in every profile.
- The GitHub ranges are a snapshot. Refresh them when GitHub adds ranges.
- A scratch home allows only Fully isolated, and needs a warm pool for the runtime. Without a pool, the claim does not get a Pod and the agent never connects.
- A scratch home keeps the agent token in plain text in a Pod annotation and in the SandboxClaim. Anyone who can read Pods or SandboxClaims in the namespace can read it. Keep read access to the namespace tight.
- On Amazon VPC CNI, a Pod can lose its rules while it runs. All Pods of one warm pool on one node share rules, and deleting any of them, such as a scratch workspace that stops, can delete the rules of the others. A claimed scratch Pod is then open until the next check. The check runs every 5 s, so the agent stops within about 5 s, the container exits, and the workspace is offline until Kubernetes restarts the container and the check passes again. If the rules do not come back, the container keeps restarting and the agent stays offline. Processes that do not belong to the agent stop with the container. Code that runs between two checks can reach the network for up to about 5 s.
- The policy check needs the NetworkPolicy to block the Kubernetes API server. If `coder_egress_cidrs` includes the API server address, or Public internet can reach it, set `network_policy_gate = false`. Without the check, the Pod is open until VPC CNI applies its policy.
- The workspace has no root access and no Docker.
- agent-sandbox has no stop hook. The template sets no `shutdownTime`, so the workspace TTL in Coder is the only timer.
- IPv4 only.
